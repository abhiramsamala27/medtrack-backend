import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/medication_provider.dart';

class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _durationController = TextEditingController(text: '7');
  final List<TimeOfDay> _timings = [const TimeOfDay(hour: 9, minute: 0)];

  void _save() {
    final name = _nameController.text.trim();
    final dosage = _dosageController.text.trim();
    final duration = int.tryParse(_durationController.text) ?? 7;
    final timings = _timings.map((t) => "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}").toList();

    if (name.isEmpty || dosage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are required!")));
      return;
    }

    Provider.of<MedicationProvider>(context, listen: false).addMedication(name, dosage, duration, timings);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Medication")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInputLabel("Medicine Name"),
            _buildTextField(_nameController, "e.g. Paracetamol"),
            const SizedBox(height: 20),
            _buildInputLabel("Dosage"),
            _buildTextField(_dosageController, "e.g. 500mg"),
            const SizedBox(height: 20),
            _buildInputLabel("Duration (Days)"),
            _buildTextField(_durationController, "e.g. 10", inputType: TextInputType.number),
            const SizedBox(height: 32),
            _buildInputLabel("Timings"),
            const SizedBox(height: 8),
            ..._timings.asMap().entries.map((entry) {
                   final index = entry.key;
                   final time = entry.value;
                   return _buildTimingRow(index, time);
            }),
            TextButton.icon(
              onPressed: () => setState(() => _timings.add(const TimeOfDay(hour: 12, minute: 0))),
              icon: const Icon(Icons.add),
              label: const Text("Add Another Time"),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                   backgroundColor: Theme.of(context).colorScheme.primary,
                   foregroundColor: Colors.white,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("Save Medication", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {TextInputType inputType = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildTimingRow(int index, TimeOfDay time) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked != null) setState(() => _timings[index] = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(time.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        if (_timings.length > 1) IconButton(onPressed: () => setState(() => _timings.removeAt(index)), icon: const Icon(Icons.remove_circle_outline, color: Colors.red)),
      ],
    );
  }
}
