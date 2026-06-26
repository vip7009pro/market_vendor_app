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
      className="rounded-xl overflow-hidden border border-white/5 bg-slate-900/50 mt-6 w-full h-[480px] lg:h-[calc(100vh-270px)] min-h-[350px]"
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
          '--DataGrid-containerBackground': '#1e293b',
          '& .MuiDataGrid-columnHeaders': { backgroundColor: '#0f172a' },
          '& .MuiDataGrid-cell': { borderColor: 'rgba(148, 163, 184, 0.08)' },
          '& .MuiDataGrid-row:hover': { backgroundColor: 'rgba(255,255,255,0.03)' },
          '& .MuiDataGrid-row.Mui-selected': {
            backgroundColor: 'rgba(99, 102, 241, 0.15) !important',
            '&:hover': { backgroundColor: 'rgba(99, 102, 241, 0.2) !important' },
          },
          '& .MuiDataGrid-footerContainer': { borderTop: '1px solid rgba(148, 163, 184, 0.12)' },
          '& .MuiDataGrid-columnHeaderTitle': { fontWeight: 700, fontSize: '0.7rem', textTransform: 'uppercase', letterSpacing: '0.05em' },
          ...sx,
        }}
      />
    </div>
  );
}
