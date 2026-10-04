import prisma from '../config/database.js';
import { Prisma } from '@prisma/client';

export class SyncService {
  private static parseDate(v: any): Date {
    if (!v) return new Date();
    const d = new Date(v);
    return isNaN(d.getTime()) ? new Date() : d;
  }

  private static parseDateOrNull(v: any): Date | null {
    if (!v) return null;
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }

  static async pushEvents(userId: number, deviceId: string, events: any[]) {
    const CHUNK_SIZE = 50;
    let totalInserted = 0;

    for (let i = 0; i < events.length; i += CHUNK_SIZE) {
      const chunk = events.slice(i, i + CHUNK_SIZE);
      const insertedCount = await prisma.$transaction(async (tx) => {
        let count = 0;

        for (const ev of chunk) {
          const { eventUuid, entity, entityId, op, payload, clientUpdatedAt } = ev;
          if (!entity || !entityId || !op) continue;

          // Idempotency check
          const exist = await tx.appliedSyncEvent.findUnique({
            where: { userId_eventUuid: { userId, eventUuid } }
          });
          if (exist) continue;

          const updatedAtDate = this.parseDate(clientUpdatedAt);

          // 1. Record applied sync event
          await tx.appliedSyncEvent.create({
            data: { userId, eventUuid, appliedAt: new Date() }
          });

          // 2. Save event history
          await tx.syncEvent.create({
            data: {
              userId,
              deviceId,
              entity,
              entityId,
              op,
              payload: payload ? payload : Prisma.JsonNull,
              clientUpdatedAt: updatedAtDate,
              eventUuid,
              serverReceivedAt: new Date()
            }
          });

          // 3. Apply changes (LWW logic)
          if (op === 'delete') {
            await this.applyDeleteLww(tx, userId, entity, entityId, updatedAtDate);
          } else if (op === 'upsert' && payload) {
            await this.applyUpsertLww(tx, userId, entity, entityId, payload, updatedAtDate);
          }

          count++;
        }

        return count;
      }, {
        maxWait: 30000, // 30s max wait to obtain connection
        timeout: 120000, // 120s timeout for transaction (prevents P2028 timeout)
      });

      totalInserted += insertedCount;
    }

    return totalInserted;
  }

  private static async applyDeleteLww(tx: Prisma.TransactionClient, userId: number, entity: string, entityId: string, deletedAt: Date) {
    const data = { deletedAt, updatedAt: deletedAt };

    switch (entity) {
      case 'products':
        await tx.product.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'customers':
        await tx.customer.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'employees':
        await tx.employee.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'expenses':
        await tx.expense.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'purchase_orders':
        await tx.purchaseOrder.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'purchase_history':
        await tx.purchaseHistory.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'debts':
        await tx.debt.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'debt_payments':
        await tx.debtPayment.updateMany({
          where: { userId, uuid: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'sales':
        await tx.sale.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'vietqr_bank_accounts':
        await tx.vietqrBankAccount.updateMany({
          where: { userId, id: entityId, OR: [{ updatedAt: { lt: deletedAt } }, { updatedAt: undefined }] },
          data
        });
        break;
      case 'debt_reminder_settings':
        await tx.debtReminderSetting.deleteMany({
          where: { userId, debtId: entityId }
        });
        break;
      case 'product_opening_stocks': {
        const parts = entityId.split(':');
        if (parts.length >= 3) {
          await tx.productOpeningStock.deleteMany({
            where: { userId, productId: parts[0], year: parseInt(parts[1], 10), month: parseInt(parts[2], 10) }
          });
        }
        break;
      }
      default:
        break;
    }
  }

  private static async applyUpsertLww(tx: Prisma.TransactionClient, userId: number, entity: string, entityId: string, p: any, updatedAt: Date) {
    const shouldUpdate = async (model: any, whereClause: any): Promise<boolean> => {
      const local = await model.findUnique({ where: whereClause });
      if (!local) return true;
      return updatedAt > new Date(local.updatedAt);
    };

    switch (entity) {
      case 'products': {
        if (await shouldUpdate(tx.product, { userId_id: { userId, id: entityId } })) {
          await tx.product.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              name: p.name ?? '',
              price: Number(p.price ?? 0),
              costPrice: Number(p.costPrice ?? 0),
              currentStock: Number(p.currentStock ?? 0),
              unit: p.unit ?? '',
              barcode: p.barcode ?? null,
              isActive: p.isActive === true || p.isActive === 1 || p.isActive === '1',
              itemType: p.itemType ?? 'RAW',
              isStocked: p.isStocked === true || p.isStocked === 1 || p.isStocked === '1',
              imagePath: p.imagePath ?? null,
              updatedAt
            },
            update: {
              name: p.name ?? '',
              price: Number(p.price ?? 0),
              costPrice: Number(p.costPrice ?? 0),
              currentStock: Number(p.currentStock ?? 0),
              unit: p.unit ?? '',
              barcode: p.barcode ?? null,
              isActive: p.isActive === true || p.isActive === 1 || p.isActive === '1',
              itemType: p.itemType ?? 'RAW',
              isStocked: p.isStocked === true || p.isStocked === 1 || p.isStocked === '1',
              imagePath: p.imagePath ?? null,
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'customers': {
        if (await shouldUpdate(tx.customer, { userId_id: { userId, id: entityId } })) {
          await tx.customer.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              name: p.name ?? '',
              phone: p.phone ?? null,
              note: p.note ?? null,
              isSupplier: p.isSupplier === true || p.isSupplier === 1 || p.isSupplier === '1',
              updatedAt
            },
            update: {
              name: p.name ?? '',
              phone: p.phone ?? null,
              note: p.note ?? null,
              isSupplier: p.isSupplier === true || p.isSupplier === 1 || p.isSupplier === '1',
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'employees': {
        if (await shouldUpdate(tx.employee, { userId_id: { userId, id: entityId } })) {
          await tx.employee.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              name: p.name ?? '',
              updatedAt
            },
            update: {
              name: p.name ?? '',
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'expenses': {
        if (await shouldUpdate(tx.expense, { userId_id: { userId, id: entityId } })) {
          await tx.expense.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              occurredAt: this.parseDate(p.occurredAt),
              amount: Number(p.amount ?? 0),
              category: p.category ?? '',
              note: p.note ?? null,
              expenseDocUploaded: p.expenseDocUploaded === true || p.expenseDocUploaded === 1 || p.expenseDocUploaded === '1',
              expenseDocFileId: p.expenseDocFileId ?? null,
              expenseDocUpdatedAt: this.parseDateOrNull(p.expenseDocUpdatedAt),
              updatedAt
            },
            update: {
              occurredAt: this.parseDate(p.occurredAt),
              amount: Number(p.amount ?? 0),
              category: p.category ?? '',
              note: p.note ?? null,
              expenseDocUploaded: p.expenseDocUploaded === true || p.expenseDocUploaded === 1 || p.expenseDocUploaded === '1',
              expenseDocFileId: p.expenseDocFileId ?? null,
              expenseDocUpdatedAt: this.parseDateOrNull(p.expenseDocUpdatedAt),
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'purchase_orders': {
        if (await shouldUpdate(tx.purchaseOrder, { userId_id: { userId, id: entityId } })) {
          await tx.purchaseOrder.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              createdAt: this.parseDate(p.createdAt),
              supplierName: p.supplierName ?? null,
              supplierPhone: p.supplierPhone ?? null,
              discountType: p.discountType ?? 'AMOUNT',
              discountValue: Number(p.discountValue ?? 0),
              paidAmount: Number(p.paidAmount ?? 0),
              note: p.note ?? null,
              purchaseDocUploaded: p.purchaseDocUploaded === true || p.purchaseDocUploaded === 1 || p.purchaseDocUploaded === '1',
              purchaseDocFileId: p.purchaseDocFileId ?? null,
              purchaseDocUpdatedAt: this.parseDateOrNull(p.purchaseDocUpdatedAt),
              updatedAt
            },
            update: {
              createdAt: this.parseDate(p.createdAt),
              supplierName: p.supplierName ?? null,
              supplierPhone: p.supplierPhone ?? null,
              discountType: p.discountType ?? 'AMOUNT',
              discountValue: Number(p.discountValue ?? 0),
              paidAmount: Number(p.paidAmount ?? 0),
              note: p.note ?? null,
              purchaseDocUploaded: p.purchaseDocUploaded === true || p.purchaseDocUploaded === 1 || p.purchaseDocUploaded === '1',
              purchaseDocFileId: p.purchaseDocFileId ?? null,
              purchaseDocUpdatedAt: this.parseDateOrNull(p.purchaseDocUpdatedAt),
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'purchase_history': {
        if (await shouldUpdate(tx.purchaseHistory, { userId_id: { userId, id: entityId } })) {
          await tx.purchaseHistory.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              createdAt: this.parseDate(p.createdAt),
              productId: p.productId ?? '',
              productName: p.productName ?? '',
              quantity: Number(p.quantity ?? 0),
              unitCost: Number(p.unitCost ?? 0),
              totalCost: Number(p.totalCost ?? 0),
              paidAmount: Number(p.paidAmount ?? 0),
              supplierName: p.supplierName ?? null,
              supplierPhone: p.supplierPhone ?? null,
              note: p.note ?? null,
              purchaseDocUploaded: p.purchaseDocUploaded === true || p.purchaseDocUploaded === 1 || p.purchaseDocUploaded === '1',
              purchaseDocFileId: p.purchaseDocFileId ?? null,
              purchaseDocUpdatedAt: this.parseDateOrNull(p.purchaseDocUpdatedAt),
              purchaseOrderId: p.purchaseOrderId ?? null,
              updatedAt
            },
            update: {
              createdAt: this.parseDate(p.createdAt),
              productId: p.productId ?? '',
              productName: p.productName ?? '',
              quantity: Number(p.quantity ?? 0),
              unitCost: Number(p.unitCost ?? 0),
              totalCost: Number(p.totalCost ?? 0),
              paidAmount: Number(p.paidAmount ?? 0),
              supplierName: p.supplierName ?? null,
              supplierPhone: p.supplierPhone ?? null,
              note: p.note ?? null,
              purchaseDocUploaded: p.purchaseDocUploaded === true || p.purchaseDocUploaded === 1 || p.purchaseDocUploaded === '1',
              purchaseDocFileId: p.purchaseDocFileId ?? null,
              purchaseDocUpdatedAt: this.parseDateOrNull(p.purchaseDocUpdatedAt),
              purchaseOrderId: p.purchaseOrderId ?? null,
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'debts': {
        if (await shouldUpdate(tx.debt, { userId_id: { userId, id: entityId } })) {
          await tx.debt.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              createdAt: this.parseDate(p.createdAt),
              type: Number(p.type ?? 0),
              partyId: p.partyId ?? '',
              partyName: p.partyName ?? '',
              initialAmount: Number(p.initialAmount ?? 0),
              amount: Number(p.amount ?? 0),
              description: p.description ?? null,
              dueDate: this.parseDateOrNull(p.dueDate),
              settled: p.settled === true || p.settled === 1 || p.settled === '1',
              sourceType: p.sourceType ?? null,
              sourceId: p.sourceId ?? null,
              updatedAt
            },
            update: {
              createdAt: this.parseDate(p.createdAt),
              type: Number(p.type ?? 0),
              partyId: p.partyId ?? '',
              partyName: p.partyName ?? '',
              initialAmount: Number(p.initialAmount ?? 0),
              amount: Number(p.amount ?? 0),
              description: p.description ?? null,
              dueDate: this.parseDateOrNull(p.dueDate),
              settled: p.settled === true || p.settled === 1 || p.settled === '1',
              sourceType: p.sourceType ?? null,
              sourceId: p.sourceId ?? null,
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'debt_payments': {
        if (await shouldUpdate(tx.debtPayment, { userId_uuid: { userId, uuid: entityId } })) {
          await tx.debtPayment.upsert({
            where: { userId_uuid: { userId, uuid: entityId } },
            create: {
              userId,
              uuid: entityId,
              debtId: p.debtId ?? '',
              amount: Number(p.amount ?? 0),
              note: p.note ?? null,
              paymentType: p.paymentType ?? null,
              createdAt: this.parseDate(p.createdAt),
              updatedAt
            },
            update: {
              debtId: p.debtId ?? '',
              amount: Number(p.amount ?? 0),
              note: p.note ?? null,
              paymentType: p.paymentType ?? null,
              createdAt: this.parseDate(p.createdAt),
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'vietqr_bank_accounts': {
        if (await shouldUpdate(tx.vietqrBankAccount, { userId_id: { userId, id: entityId } })) {
          await tx.vietqrBankAccount.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              bankApiId: p.bankApiId ? Number(p.bankApiId) : null,
              name: p.name ?? null,
              code: p.code ?? null,
              bin: p.bin ?? null,
              shortName: p.shortName ?? p.short_name ?? null,
              logo: p.logo ?? null,
              transferSupported: p.transferSupported === true || p.transferSupported === 1 || p.transferSupported === '1',
              lookupSupported: p.lookupSupported === true || p.lookupSupported === 1 || p.lookupSupported === '1',
              support: p.support ? Number(p.support) : null,
              isTransfer: p.isTransfer === true || p.isTransfer === 1 || p.isTransfer === '1',
              swiftCode: p.swiftCode ?? p.swift_code ?? null,
              accountNo: p.accountNo ?? '',
              accountName: p.accountName ?? '',
              isDefault: p.isDefault === true || p.isDefault === 1 || p.isDefault === '1',
              updatedAt
            },
            update: {
              bankApiId: p.bankApiId ? Number(p.bankApiId) : null,
              name: p.name ?? null,
              code: p.code ?? null,
              bin: p.bin ?? null,
              shortName: p.shortName ?? p.short_name ?? null,
              logo: p.logo ?? null,
              transferSupported: p.transferSupported === true || p.transferSupported === 1 || p.transferSupported === '1',
              lookupSupported: p.lookupSupported === true || p.lookupSupported === 1 || p.lookupSupported === '1',
              support: p.support ? Number(p.support) : null,
              isTransfer: p.isTransfer === true || p.isTransfer === 1 || p.isTransfer === '1',
              swiftCode: p.swiftCode ?? p.swift_code ?? null,
              accountNo: p.accountNo ?? '',
              accountName: p.accountName ?? '',
              isDefault: p.isDefault === true || p.isDefault === 1 || p.isDefault === '1',
              deletedAt: null,
              updatedAt
            }
          });
        }
        break;
      }

      case 'sales': {
        if (await shouldUpdate(tx.sale, { userId_id: { userId, id: entityId } })) {
          await tx.sale.upsert({
            where: { userId_id: { userId, id: entityId } },
            create: {
              userId,
              id: entityId,
              createdAt: this.parseDate(p.createdAt),
              customerId: p.customerId ?? null,
              customerName: p.customerName ?? null,
              employeeId: p.employeeId ?? null,
              employeeName: p.employeeName ?? null,
              discount: Number(p.discount ?? 0),
              paidAmount: Number(p.paidAmount ?? 0),
              paymentType: p.paymentType ?? null,
              totalCost: Number(p.totalCost ?? 0),
              note: p.note ?? null,
              updatedAt
            },
            update: {
              createdAt: this.parseDate(p.createdAt),
              customerId: p.customerId ?? null,
              customerName: p.customerName ?? null,
              employeeId: p.employeeId ?? null,
              employeeName: p.employeeName ?? null,
              discount: Number(p.discount ?? 0),
              paidAmount: Number(p.paidAmount ?? 0),
              paymentType: p.paymentType ?? null,
              totalCost: Number(p.totalCost ?? 0),
              note: p.note ?? null,
              deletedAt: null,
              updatedAt
            }
          });

          // Soft delete existing sale items
          await tx.saleItem.updateMany({
            where: { userId, saleId: entityId, updatedAt: { lt: updatedAt } },
            data: { deletedAt: updatedAt, updatedAt }
          });

          // Apply new embedded sale items
          const items = Array.isArray(p.items) ? p.items : [];
          for (let i = 0; i < items.length; i++) {
            const it = items[i];
            const localIdRaw = it.id ?? it.localId ?? i;
            const itemId = `${entityId}:${localIdRaw}`;

            await tx.saleItem.upsert({
              where: { userId_id: { userId, id: itemId } },
              create: {
                userId,
                id: itemId,
                saleId: entityId,
                productId: it.productId ?? null,
                name: it.name ?? '',
                unitPrice: Number(it.unitPrice ?? 0),
                unitCost: Number(it.unitCost ?? 0),
                quantity: Number(it.quantity ?? 0),
                unit: it.unit ?? '',
                itemType: it.itemType ?? null,
                displayName: it.displayName ?? null,
                mixItemsJson: it.mixItemsJson ?? null,
                updatedAt
              },
              update: {
                productId: it.productId ?? null,
                name: it.name ?? '',
                unitPrice: Number(it.unitPrice ?? 0),
                unitCost: Number(it.unitCost ?? 0),
                quantity: Number(it.quantity ?? 0),
                unit: it.unit ?? '',
                itemType: it.itemType ?? null,
                displayName: it.displayName ?? null,
                mixItemsJson: it.mixItemsJson ?? null,
                deletedAt: null,
                updatedAt
              }
            });
          }
        }
        break;
      }

      case 'store_info': {
        const storeId = parseInt(p.id ?? entityId ?? '1', 10) || 1;
        await tx.storeInfo.upsert({
          where: { userId_id: { userId, id: storeId } },
          create: {
            userId,
            id: storeId,
            name: p.name ?? '',
            address: p.address ?? '',
            phone: p.phone ?? '',
            taxCode: p.taxCode ?? p.tax_code ?? null,
            email: p.email ?? null,
            bankName: p.bankName ?? p.bank_name ?? null,
            bankAccount: p.bankAccount ?? p.bank_account ?? null,
            updatedAt
          },
          update: {
            name: p.name ?? '',
            address: p.address ?? '',
            phone: p.phone ?? '',
            taxCode: p.taxCode ?? p.tax_code ?? null,
            email: p.email ?? null,
            bankName: p.bankName ?? p.bank_name ?? null,
            bankAccount: p.bankAccount ?? p.bank_account ?? null,
            updatedAt
          }
        });
        break;
      }

      case 'product_opening_stocks': {
        const parts = entityId.split(':');
        const prodId = p.productId ?? parts[0];
        const yr = parseInt(p.year ?? parts[1] ?? '0', 10);
        const mo = parseInt(p.month ?? parts[2] ?? '0', 10);
        if (prodId && yr && mo) {
          await tx.productOpeningStock.upsert({
            where: { userId_productId_year_month: { userId, productId: prodId, year: yr, month: mo } },
            create: {
              userId,
              productId: prodId,
              year: yr,
              month: mo,
              openingStock: Number(p.openingStock ?? p.opening_stock ?? 0),
              updatedAt
            },
            update: {
              openingStock: Number(p.openingStock ?? p.opening_stock ?? 0),
              updatedAt
            }
          });
        }
        break;
      }

      case 'debt_reminder_settings': {
        const dId = p.debtId ?? entityId;
        if (dId) {
          await tx.debtReminderSetting.upsert({
            where: { userId_debtId: { userId, debtId: dId } },
            create: {
              userId,
              debtId: dId,
              muted: p.muted === true || p.muted === 1 || p.muted === '1',
              lastNotifiedAt: this.parseDateOrNull(p.lastNotifiedAt ?? p.last_notified_at)
            },
            update: {
              muted: p.muted === true || p.muted === 1 || p.muted === '1',
              lastNotifiedAt: this.parseDateOrNull(p.lastNotifiedAt ?? p.last_notified_at)
            }
          });
        }
        break;
      }

      default:
        break;
    }
  }

  static async pullEvents(userId: number, cursor: number, limit: number) {
    const events = await prisma.syncEvent.findMany({
      where: { userId, eventId: { gt: cursor } },
      orderBy: { eventId: 'asc' },
      take: limit
    });

    const maxEventId = events.length > 0 ? events[events.length - 1].eventId : cursor;

    return {
      cursor: maxEventId,
      events: events.map((ev) => ({
        eventId: ev.eventId,
        eventUuid: ev.eventUuid,
        deviceId: ev.deviceId,
        entity: ev.entity,
        entityId: ev.entityId,
        op: ev.op,
        payload: ev.payload,
        clientUpdatedAt: ev.clientUpdatedAt.toISOString()
      }))
    };
  }

  static async getSnapshot(userId: number) {
    const [
      products,
      customers,
      sales,
      debts,
      debtPayments,
      purchaseOrders,
      purchaseHistories,
      expenses,
      employees,
      vietqrBankAccounts,
      storeInfo,
      productOpeningStocks,
      debtReminderSettings
    ] = await Promise.all([
      prisma.product.findMany({ where: { userId, deletedAt: null } }),
      prisma.customer.findMany({ where: { userId, deletedAt: null } }),
      prisma.sale.findMany({
        where: { userId, deletedAt: null },
        include: { items: { where: { deletedAt: null } } }
      }),
      prisma.debt.findMany({ where: { userId, deletedAt: null } }),
      prisma.debtPayment.findMany({ where: { userId, deletedAt: null } }),
      prisma.purchaseOrder.findMany({ where: { userId, deletedAt: null } }),
      prisma.purchaseHistory.findMany({ where: { userId, deletedAt: null } }),
      prisma.expense.findMany({ where: { userId, deletedAt: null } }),
      prisma.employee.findMany({ where: { userId, deletedAt: null } }),
      prisma.vietqrBankAccount.findMany({ where: { userId, deletedAt: null } }),
      prisma.storeInfo.findMany({ where: { userId } }),
      prisma.productOpeningStock.findMany({ where: { userId } }),
      prisma.debtReminderSetting.findMany({ where: { userId } }),
    ]);

    return {
      products,
      customers,
      sales,
      debts,
      debtPayments,
      purchaseOrders,
      purchaseHistories,
      expenses,
      employees,
      vietqrBankAccounts,
      storeInfo,
      productOpeningStocks,
      debtReminderSettings,
      serverTime: new Date().toISOString()
    };
  }

  static async wipeUserData(userId: number) {
    return await prisma.$transaction(async (tx) => {
      // 1. Xóa các bảng con phụ thuộc trước (cascade children)
      await tx.saleItem.deleteMany({ where: { userId } });
      await tx.sale.deleteMany({ where: { userId } });
      await tx.debtPayment.deleteMany({ where: { userId } });
      await tx.debtReminderSetting.deleteMany({ where: { userId } });
      await tx.debt.deleteMany({ where: { userId } });
      await tx.purchaseHistory.deleteMany({ where: { userId } });
      await tx.purchaseOrder.deleteMany({ where: { userId } });
      await tx.expense.deleteMany({ where: { userId } });
      await tx.productOpeningStock.deleteMany({ where: { userId } });
      await tx.product.deleteMany({ where: { userId } });
      await tx.customer.deleteMany({ where: { userId } });
      await tx.employee.deleteMany({ where: { userId } });
      await tx.vietqrBankAccount.deleteMany({ where: { userId } });
      await tx.storeInfo.deleteMany({ where: { userId } });

      // 2. Xóa các bảng lưu vết đồng bộ & audit
      await tx.appliedSyncEvent.deleteMany({ where: { userId } });
      await tx.syncEvent.deleteMany({ where: { userId } });
      await tx.deletedEntity.deleteMany({ where: { userId } });
      await tx.syncLog.deleteMany({ where: { userId } });
      await tx.auditLog.deleteMany({ where: { userId } });
      await tx.outbox.deleteMany({ where: { userId } });
      await tx.syncState.deleteMany({ where: { userId } });

      return true;
    }, {
      maxWait: 30000,
      timeout: 120000,
    });
  }
}

