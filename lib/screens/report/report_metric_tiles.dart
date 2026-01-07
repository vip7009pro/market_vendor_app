part of '../report_screen.dart';

class _PaymentMetricTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final double value;
  final NumberFormat currency;
  final List<Color> gradientColors;
  final String? tooltip;
  final VoidCallback? onTap;
  const _PaymentMetricTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.currency,
    required this.gradientColors,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              currency.format(value),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
    final wrapped = (tooltip == null || tooltip!.trim().isEmpty) ? child : Tooltip(message: tooltip!, child: child);
    if (onTap == null) return wrapped;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: wrapped,
    );
  }
}

class _InventoryMetricTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final double qty;
  final double amountCost;
  final double amountSell;
  final NumberFormat currency;
  final List<Color> gradientColors;
  final String? tooltip;
  final VoidCallback? onTap;
  const _InventoryMetricTile({
    required this.title,
    required this.icon,
    required this.qty,
    required this.amountCost,
    required this.amountSell,
    required this.currency,
    required this.gradientColors,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final qtyText = qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2);
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'SL: $qtyText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'GV: ${currency.format(amountCost)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'GB: ${currency.format(amountSell)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
    final wrapped = (tooltip == null || tooltip!.trim().isEmpty) ? child : Tooltip(message: tooltip!, child: child);
    if (onTap == null) return wrapped;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: wrapped,
    );
  }
}
