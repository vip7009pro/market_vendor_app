import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';

const prisma = new PrismaClient();

const SEED_EMAIL = 'demo@marketvendor.com';
const SEED_PASSWORD = 'demo123456';

function daysAgo(n: number): Date {
  const d = new Date();
  d.setDate(d.getDate() - n);
  d.setHours(9 + (n % 8), (n * 13) % 60, 0, 0);
  return d;
}

async function main() {
  console.log('🌱 Seeding database...');

  // Clean existing seed user data
  const existing = await prisma.user.findUnique({ where: { email: SEED_EMAIL } });
  if (existing) {
    const uid = existing.id;
    await prisma.saleItem.deleteMany({ where: { userId: uid } });
    await prisma.sale.deleteMany({ where: { userId: uid } });
    await prisma.debtPayment.deleteMany({ where: { userId: uid } });
    await prisma.debt.deleteMany({ where: { userId: uid } });
    await prisma.purchaseHistory.deleteMany({ where: { userId: uid } });
    await prisma.purchaseOrder.deleteMany({ where: { userId: uid } });
    await prisma.expense.deleteMany({ where: { userId: uid } });
    await prisma.product.deleteMany({ where: { userId: uid } });
    await prisma.customer.deleteMany({ where: { userId: uid } });
    await prisma.employee.deleteMany({ where: { userId: uid } });
    await prisma.vietqrBankAccount.deleteMany({ where: { userId: uid } });
    await prisma.storeInfo.deleteMany({ where: { userId: uid } });
    await prisma.user.delete({ where: { id: uid } });
    console.log('  Cleared previous seed data');
  }

  const hashedPassword = await bcrypt.hash(SEED_PASSWORD, 12);
  const user = await prisma.user.create({
    data: {
      email: SEED_EMAIL,
      password: hashedPassword,
      name: 'Cửa hàng Demo',
    },
  });
  const userId = user.id;
  const now = new Date();

  // Store info
  await prisma.storeInfo.create({
    data: {
      userId,
      name: 'Tiệm Tạp Hóa Demo Market',
      address: '123 Nguyễn Huệ, Quận 1, TP.HCM',
      phone: '0901234567',
      updatedAt: now,
    },
  });

  // Bank account with VietQR BIN
  await prisma.vietqrBankAccount.create({
    data: {
      userId,
      id: uuidv4(),
      name: 'Ngân hàng TMCP Ngoại thương Việt Nam',
      code: 'VCB',
      bin: '970436',
      shortName: 'Vietcombank',
      accountNo: '1234567890',
      accountName: 'NGUYEN VAN DEMO',
      isDefault: true,
      updatedAt: now,
    },
  });

  // Employees
  const employees = [
    { id: 'emp-001', name: 'Nguyễn Văn A' },
    { id: 'emp-002', name: 'Trần Thị B' },
    { id: 'emp-003', name: 'Lê Văn C' },
  ];
  for (const e of employees) {
    await prisma.employee.create({ data: { userId, ...e, updatedAt: now } });
  }

  // Products - mix of RAW and MIX
  const productDefs = [
    { id: 'p-001', name: 'Cà phê sữa đá', price: 25000, costPrice: 12000, stock: 200, unit: 'ly', itemType: 'MIX' },
    { id: 'p-002', name: 'Cà phê đen đá', price: 20000, costPrice: 10000, stock: 300, unit: 'ly', itemType: 'MIX' },
    { id: 'p-003', name: 'Trà đào cam sả', price: 35000, costPrice: 15000, stock: 150, unit: 'ly', itemType: 'MIX' },
    { id: 'p-004', name: 'Bánh mì thịt nướng', price: 20000, costPrice: 11000, stock: 50, unit: 'ổ', itemType: 'MIX' },
    { id: 'p-005', name: 'Nước ngọt Coca Cola', price: 15000, costPrice: 10500, stock: 240, unit: 'lon', itemType: 'RAW', barcode: '8930001010101' },
    { id: 'p-006', name: 'Nước suối Lavie', price: 8000, costPrice: 4500, stock: 500, unit: 'chai', itemType: 'RAW' },
    { id: 'p-007', name: 'Khăn giấy ướt', price: 5000, costPrice: 2000, stock: 180, unit: 'gói', itemType: 'RAW' },
    { id: 'p-008', name: 'Mì gói Hảo Hảo', price: 4500, costPrice: 3200, stock: 400, unit: 'gói', itemType: 'RAW' },
    { id: 'p-009', name: 'Sữa tươi TH true MILK', price: 12000, costPrice: 8500, stock: 120, unit: 'hộp', itemType: 'RAW' },
    { id: 'p-010', name: 'Gạo ST25', price: 28000, costPrice: 22000, stock: 80, unit: 'kg', itemType: 'RAW' },
    { id: 'p-011', name: 'Dầu ăn Neptune', price: 55000, costPrice: 48000, stock: 60, unit: 'chai', itemType: 'RAW' },
    { id: 'p-012', name: 'Đường trắng', price: 22000, costPrice: 18000, stock: 100, unit: 'kg', itemType: 'RAW' },
    { id: 'p-013', name: 'Trà sữa trân châu', price: 30000, costPrice: 14000, stock: 100, unit: 'ly', itemType: 'MIX' },
    { id: 'p-014', name: 'Bia Tiger', price: 18000, costPrice: 13500, stock: 200, unit: 'lon', itemType: 'RAW' },
    { id: 'p-015', name: 'Snack Oishi', price: 10000, costPrice: 6500, stock: 300, unit: 'gói', itemType: 'RAW' },
    { id: 'p-016', name: 'Xăng thơm', price: 35000, costPrice: 25000, stock: 40, unit: 'chai', itemType: 'RAW' },
    { id: 'p-017', name: 'Nước mắm Nam Ngư', price: 32000, costPrice: 26000, stock: 70, unit: 'chai', itemType: 'RAW' },
    { id: 'p-018', name: 'Combo sáng', price: 45000, costPrice: 25000, stock: 0, unit: 'suất', itemType: 'MIX' },
    { id: 'p-019', name: 'Kem Wall\'s', price: 12000, costPrice: 8000, stock: 90, unit: 'cây', itemType: 'RAW' },
    { id: 'p-020', name: 'Thuốc lá 555', price: 25000, costPrice: 23000, stock: 150, unit: 'bao', itemType: 'RAW' },
  ];

  for (const p of productDefs) {
    await prisma.product.create({
      data: {
        userId,
        id: p.id,
        name: p.name,
        price: p.price,
        costPrice: p.costPrice,
        currentStock: p.stock,
        unit: p.unit,
        barcode: (p as any).barcode || null,
        itemType: p.itemType,
        isActive: true,
        isStocked: true,
        updatedAt: now,
      },
    });
  }

  // Customers
  const customerDefs = [
    { id: 'c-001', name: 'Chị Lan Chợ Lớn', phone: '0901111111', isSupplier: false },
    { id: 'c-002', name: 'Anh Hùng Đại Lý', phone: '0902222222', isSupplier: false },
    { id: 'c-003', name: 'Cô Mai', phone: '0903333333', isSupplier: false },
    { id: 'c-004', name: 'Chú Tư', phone: '0904444444', isSupplier: false },
    { id: 'c-005', name: 'Bà Sáu', phone: '0905555555', isSupplier: false },
    { id: 'c-006', name: 'Anh Phong', phone: '0906666666', isSupplier: false },
    { id: 'c-007', name: 'Chị Hoa Spa', phone: '0907777777', isSupplier: false },
    { id: 'c-008', name: 'Quán Cơm Bà Năm', phone: '0908888888', isSupplier: false },
    { id: 's-001', name: 'Công ty TNHH Coca Cola VN', phone: '0281234567', isSupplier: true },
    { id: 's-002', name: 'Nhà cung cấp Hạt Cà Phê Trung Nguyên', phone: '0282345678', isSupplier: true },
    { id: 's-003', name: 'Vinamilk Distribution', phone: '0283456789', isSupplier: true },
    { id: 's-004', name: 'NCC Bánh mì Sài Gòn', phone: '0284567890', isSupplier: true },
  ];

  for (const c of customerDefs) {
    await prisma.customer.create({
      data: { userId, ...c, updatedAt: now },
    });
  }

  // Generate 60 sales over last 90 days
  const customerNames = customerDefs.filter(c => !c.isSupplier);
  let saleCount = 0;

  for (let day = 0; day < 90; day += 1) {
    const salesPerDay = day % 7 === 0 ? 0 : (day % 3 === 0 ? 2 : 1);
    for (let s = 0; s < salesPerDay; s++) {
      saleCount++;
      const saleId = `seed-sale-${String(saleCount).padStart(4, '0')}`;
      const createdAt = daysAgo(day);
      const cust = customerNames[saleCount % customerNames.length];
      const isWalkIn = saleCount % 11 === 0;
      const emp = employees[saleCount % employees.length];

      const numItems = 1 + (saleCount % 4);
      const items: Array<{
        productId: string;
        name: string;
        unitPrice: number;
        unitCost: number;
        quantity: number;
        unit: string;
        itemType: string;
      }> = [];

      let subtotal = 0;
      for (let i = 0; i < numItems; i++) {
        const prod = productDefs[(saleCount + i) % productDefs.length];
        const qty = 1 + ((saleCount + i) % 5);
        const lineTotal = prod.price * qty;
        subtotal += lineTotal;
        items.push({
          productId: prod.id,
          name: prod.name,
          unitPrice: prod.price,
          unitCost: prod.costPrice,
          quantity: qty,
          unit: prod.unit,
          itemType: prod.itemType,
        });
      }

      const discount = saleCount % 5 === 0 ? 10000 : 0;
      const total = Math.max(0, subtotal - discount);
      const paymentType = saleCount % 3 === 0 ? 'BANK' : 'CASH';
      let paidAmount = total;
      if (saleCount % 7 === 0) paidAmount = 0;
      else if (saleCount % 4 === 0) paidAmount = Math.floor(total * 0.5);

      const totalCost = items.reduce((sum, it) => sum + it.unitCost * it.quantity, 0);

      await prisma.sale.create({
        data: {
          userId,
          id: saleId,
          createdAt,
          customerId: isWalkIn ? null : cust.id,
          customerName: isWalkIn ? 'Khách vãng lai' : cust.name,
          employeeId: emp.id,
          employeeName: emp.name,
          discount,
          paidAmount,
          paymentType,
          totalCost,
          note: saleCount % 8 === 0 ? 'Giao hàng tận nơi' : null,
          updatedAt: createdAt,
        },
      });

      await prisma.saleItem.createMany({
        data: items.map((it) => ({
          userId,
          saleId,
          productId: it.productId,
          name: it.name,
          unitPrice: it.unitPrice,
          unitCost: it.unitCost,
          quantity: it.quantity,
          unit: it.unit,
          itemType: it.itemType,
          updatedAt: createdAt,
        })),
      });

      // Create debt if underpaid and not walk-in
      if (paidAmount < total && !isWalkIn) {
        const debtAmount = total - paidAmount;
        await prisma.debt.create({
          data: {
            userId,
            id: uuidv4(),
            createdAt,
            type: 1,
            partyId: cust.id,
            partyName: cust.name,
            initialAmount: debtAmount,
            amount: debtAmount,
            description: `Nợ từ đơn bán ${saleId.slice(-6)}`,
            sourceType: 'sale',
            sourceId: saleId,
            updatedAt: createdAt,
          },
        });
      }
    }
  }

  // Purchase orders
  const suppliers = customerDefs.filter(c => c.isSupplier);
  for (let i = 1; i <= 15; i++) {
    const poId = `seed-po-${String(i).padStart(3, '0')}`;
    const createdAt = daysAgo(i * 5);
    const supplier = suppliers[i % suppliers.length];
    const prod = productDefs.filter(p => p.itemType === 'RAW')[i % 10];
    const qty = 20 + i * 10;
    const unitCost = prod.costPrice;
    const subtotal = qty * unitCost;
    const discount = i % 3 === 0 ? 50000 : 0;
    const total = Math.max(0, subtotal - discount);
    const paid = i % 4 === 0 ? 0 : (i % 2 === 0 ? Math.floor(total * 0.6) : total);

    await prisma.purchaseOrder.create({
      data: {
        userId,
        id: poId,
        createdAt,
        supplierName: supplier.name,
        supplierPhone: supplier.phone,
        discountType: 'AMOUNT',
        discountValue: discount,
        paidAmount: paid,
        note: `Nhập lô hàng tháng ${i}`,
        updatedAt: createdAt,
      },
    });

    await prisma.purchaseHistory.create({
      data: {
        userId,
        id: uuidv4(),
        createdAt,
        productId: prod.id,
        productName: prod.name,
        quantity: qty,
        unitCost,
        totalCost: subtotal,
        paidAmount: paid,
        supplierName: supplier.name,
        supplierPhone: supplier.phone,
        purchaseOrderId: poId,
        updatedAt: createdAt,
      },
    });

    if (paid < total) {
      await prisma.debt.create({
        data: {
          userId,
          id: uuidv4(),
          createdAt,
          type: 0,
          partyId: supplier.id,
          partyName: supplier.name,
          initialAmount: total - paid,
          amount: total - paid,
          description: `Nợ nhập hàng ${poId.slice(-6)}`,
          sourceType: 'purchase',
          sourceId: poId,
          updatedAt: createdAt,
        },
      });
    }
  }

  // Expenses
  const expenseCategories = ['Tiền điện', 'Tiền nước', 'Tiền thuê mặt bằng', 'Lương nhân viên', 'Vận chuyển', 'Marketing', 'Sửa chữa', 'Khác'];
  for (let i = 1; i <= 30; i++) {
    await prisma.expense.create({
      data: {
        userId,
        id: uuidv4(),
        occurredAt: daysAgo(i * 2),
        amount: 100000 + (i * 50000),
        category: expenseCategories[i % expenseCategories.length],
        note: `Chi phí tháng - khoản ${i}`,
        updatedAt: daysAgo(i * 2),
      },
    });
  }

  console.log(`✅ Seed completed!`);
  console.log(`   Email:    ${SEED_EMAIL}`);
  console.log(`   Password: ${SEED_PASSWORD}`);
  console.log(`   Products: ${productDefs.length}`);
  console.log(`   Customers: ${customerDefs.filter(c => !c.isSupplier).length}`);
  console.log(`   Suppliers: ${suppliers.length}`);
  console.log(`   Sales:    ${saleCount}`);
  console.log(`   Purchases: 15`);
  console.log(`   Expenses: 30`);
}

main()
  .catch((e) => {
    console.error('Seed failed:', e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
