'use client';

import React from 'react';
import { DataGrid, DataGridProps, GridRowId } from '@mui/x-data-grid';
import { viVN } from '@mui/x-data-grid/locales';

type AppDataGridProps = DataGridProps & {
  height?: number | string;
};

export function toRowSelectionModel(ids: GridRowId[]) {
  return { type: 'include' as const, ids: new Set(ids) };
}

export default function AppDataGrid({
  height,
  sx,
  ...props
}: AppDataGridProps) {
  return (
    <div
      style={height !== undefined ? { width: '100%', height } : { width: '100%' }}
      className="rounded-xl overflow-hidden border border-[var(--color-border)] bg-[var(--color-bg-secondary)] mt-6 w-full h-[480px] lg:h-[calc(100vh-270px)] min-h-[350px]"
    >
      <DataGrid
        density="compact"
        pageSizeOptions={[25, 50, 100]}
        initialState={{ pagination: { paginationModel: { pageSize: 25, page: 0 } } }}
        disableRowSelectionOnClick={props.disableRowSelectionOnClick ?? false}
        localeText={viVN.components.MuiDataGrid.defaultProps.localeText}
        {...props}
        sx={{
          border: 'none',
          fontSize: '0.8125rem',
          color: 'var(--color-text)',
          backgroundColor: 'var(--color-bg-secondary)',
          '--DataGrid-containerBackground': 'var(--color-bg-secondary)',
          '& .MuiDataGrid-main': { backgroundColor: 'var(--color-bg-secondary)' },
          '& .MuiDataGrid-virtualScroller': { backgroundColor: 'var(--color-bg-secondary)' },
          '& .MuiDataGrid-columnHeaders': { backgroundColor: 'var(--color-bg-card) !important', borderBottom: '1px solid var(--color-border)' },
          '& .MuiDataGrid-columnHeader': { backgroundColor: 'var(--color-bg-card) !important' },
          '& .MuiDataGrid-cell': { borderColor: 'var(--color-border)', color: 'var(--color-text)' },
          '& .MuiDataGrid-row:hover': { backgroundColor: 'var(--color-bg-elevated) !important' },
          '& .MuiDataGrid-row.Mui-selected': {
            backgroundColor: 'rgba(99, 102, 241, 0.15) !important',
            '&:hover': { backgroundColor: 'rgba(99, 102, 241, 0.2) !important' },
          },
          '& .MuiDataGrid-footerContainer': { 
            backgroundColor: 'var(--color-bg-card) !important', 
            borderTop: '1px solid var(--color-border)',
            color: 'var(--color-text) !important'
          },
          '& .MuiTablePagination-root': { color: 'var(--color-text)' },
          '& .MuiTablePagination-actions': { color: 'var(--color-text)' },
          '& .MuiIconButton-root': { color: 'var(--color-text)' },
          '& .MuiIconButton-root.Mui-disabled': { color: 'var(--color-text-muted)', opacity: 0.5 },
          '& .MuiDataGrid-columnHeaderTitle': { fontWeight: 700, fontSize: '0.7rem', textTransform: 'uppercase', letterSpacing: '0.05em', color: 'var(--color-text-secondary) !important' },
          ...sx,
        }}
      />
    </div>
  );
}
