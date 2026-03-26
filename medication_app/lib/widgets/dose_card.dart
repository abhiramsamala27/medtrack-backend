import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/dose.dart';
import '../providers/medication_provider.dart';

class DoseCard extends StatelessWidget {
  final Dose dose;

  const DoseCard({super.key, required this.dose});

  @override
  Widget build(BuildContext context) {
    final medProvider = Provider.of<MedicationProvider>(context, listen: false);
    final timeStr = DateFormat('hh:mm a').format(dose.scheduledTime);
    final isPending = dose.status == 'PENDING';
    final isTaken = dose.status == 'TAKEN';
    final isMissed = dose.status == 'MISSED';

    Color cardColor = isTaken ? const Color(0xFFF0FDF4) : (isMissed ? const Color(0xFFFEF2F2) : Colors.white);
    Color borderColor = isTaken ? const Color(0xFFDCFCE7) : (isMissed ? const Color(0xFFFEE2E2) : Colors.grey.withOpacity(0.1));
    Color accentColor = isTaken ? const Color(0xFF22C55E) : (isMissed ? const Color(0xFFEF4444) : Theme.of(context).colorScheme.primary);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: isPending ? [
          BoxShadow(
            color: accentColor.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ] : null,
      ),
      child: Row(
        children: [
          _buildStatusIcon(isPending, isTaken, isMissed, accentColor),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.medName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  "${dose.dosage} @ $timeStr",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (isPending) ...[
            IconButton.filled(
              onPressed: () => medProvider.markDoseTaken(dose.id!), 
              icon: const Icon(Icons.check_rounded, size: 20),
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => medProvider.markDoseMissed(dose.id!),
              icon: const Icon(Icons.close_rounded, size: 20),
              style: IconButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            ),
          ] else ...[
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
               decoration: BoxDecoration(
                 color: accentColor.withOpacity(0.1),
                 borderRadius: BorderRadius.circular(12),
               ),
               child: Text(
                 dose.status,
                 style: TextStyle(color: accentColor, fontWeight: FontWeight.w700, fontSize: 11),
               ),
             ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(bool isPending, bool isTaken, bool isMissed, Color accentColor) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isTaken ? Icons.check_circle_rounded : (isMissed ? Icons.error_rounded : Icons.medication_rounded),
        color: accentColor,
        size: 26,
      ),
    );
  }
}
