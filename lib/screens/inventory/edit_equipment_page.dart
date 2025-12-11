import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../ui/custom_toast.dart';

class EditEquipmentPage extends StatefulWidget {
  final String equipmentId;
  final Map<String, dynamic> initialData;

  const EditEquipmentPage({
    super.key,
    required this.equipmentId,
    required this.initialData,
  });

  @override
  State<EditEquipmentPage> createState() => _EditEquipmentPageState();
}

class _EditEquipmentPageState extends State<EditEquipmentPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _locCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _tagsCtrl;
  late TextEditingController _imageCtrl;

  String _status = 'available';
  String _type = 'wheelchair';
  String _condition = 'good';
  DateTime? _maintenanceUntil;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _nameCtrl = TextEditingController(text: d['name'] ?? '');
    _descCtrl = TextEditingController(text: d['description'] ?? '');
    _locCtrl = TextEditingController(text: d['location'] ?? '');
    _qtyCtrl = TextEditingController(
      text: (d['quantityTotal'] ?? 1).toString(),
    );
    _priceCtrl = TextEditingController(
      text: (d['rentalPricePerDay'] ?? '').toString(),
    );
    final images = (d['images'] as List?)?.cast<String>() ?? [];
    _imageCtrl = TextEditingController(
      text: images.isNotEmpty ? images.first : '',
    );
    _status = (d['availabilityStatus'] ?? 'available').toString();
    if (d['maintenanceUntil'] is Timestamp) {
      _maintenanceUntil = (d['maintenanceUntil'] as Timestamp).toDate();
    }
    _type = (d['type'] ?? 'wheelchair').toString();
    _condition = (d['condition'] ?? 'good').toString();
    final tags = (d['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    _tagsCtrl = TextEditingController(text: tags.join(', '));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _tagsCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final price = _priceCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_priceCtrl.text);
    final tags = _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final updates = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'location': _locCtrl.text.trim(),
      'quantityTotal': qty,
      'rentalPricePerDay': price,
      'availabilityStatus': _status,
      'type': _type,
      'condition': _condition,
      'tags': tags,
      'images': _imageCtrl.text.trim().isEmpty ? [] : [_imageCtrl.text.trim()],
    };
    if (_status == 'maintenance') {
      if (_maintenanceUntil == null) {
        if (mounted) {
          ToastService.showWarning(
            context,
            'Warning',
            'Select maintenance date & time',
          );
        }
        return;
      }
      updates['needsMaintenance'] = true;
      updates['maintenanceUntil'] = Timestamp.fromDate(_maintenanceUntil!);
    } else {
      updates['needsMaintenance'] = false;
      updates['maintenanceUntil'] = null;
    }
    await CareCenterRepository.updateEquipment(widget.equipmentId, updates);

    if (!mounted) return;
    ToastService.showSuccess(context, 'Success', 'Equipment updated');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit equipment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                  TextFormField(
                    controller: _imageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Image Name',
                      prefixIcon: Icon(Icons.image_rounded),
                      hintText: 'e.g. wheelchair.png',
                      helperText: 'Enter filename from assets/images/',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.label_rounded),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.list_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'wheelchair',
                        child: Text('Wheelchair'),
                      ),
                      DropdownMenuItem(value: 'walker', child: Text('Walker')),
                      DropdownMenuItem(
                        value: 'crutches',
                        child: Text('Crutches'),
                      ),
                      DropdownMenuItem(value: 'bed', child: Text('Bed')),
                      DropdownMenuItem(
                        value: 'oxygen_machine',
                        child: Text('Oxygen machine'),
                      ),
                      DropdownMenuItem(
                        value: 'mobility_scooter',
                        child: Text('Mobility scooter'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'wheelchair'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _condition,
                    decoration: const InputDecoration(
                      labelText: 'Condition',
                      prefixIcon: Icon(Icons.fact_check_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'new', child: Text('New')),
                      DropdownMenuItem(value: 'good', child: Text('Good')),
                      DropdownMenuItem(value: 'fair', child: Text('Fair')),
                      DropdownMenuItem(
                        value: 'needs_repair',
                        child: Text('Needs repair'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _condition = v ?? 'good'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description_rounded),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter description'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      prefixIcon: Icon(Icons.place_rounded),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter location'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity total',
                      prefixIcon: Icon(Icons.countertops_rounded),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter quantity'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Rental price per day',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tagsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma separated)',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.info_outline_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'available',
                        child: Text('Available'),
                      ),
                      DropdownMenuItem(value: 'rented', child: Text('Rented')),
                      DropdownMenuItem(
                        value: 'donated',
                        child: Text('Donated'),
                      ),
                      DropdownMenuItem(
                        value: 'maintenance',
                        child: Text('Maintenance'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _status = v ?? 'available'),
                  ),
                  if (_status == 'maintenance') ...[
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.build_circle_rounded),
                      title: Text(
                        _maintenanceUntil == null
                            ? 'Maintenance until not set'
                            : 'Until: ${_maintenanceUntil!.toLocal()}',
                      ),
                      subtitle: const Text('Select both date and time'),
                      trailing: TextButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: _maintenanceUntil ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (pickedDate == null) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(
                              _maintenanceUntil ?? DateTime.now(),
                            ),
                          );
                          if (pickedTime == null) return;
                          setState(() {
                            _maintenanceUntil = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            );
                          });
                        },
                        child: const Text('Set'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}
