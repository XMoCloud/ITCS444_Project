import 'package:flutter/material.dart';
import '../../services/repository.dart';
import '../../ui/custom_toast.dart';

class AddEquipmentPage extends StatefulWidget {
  const AddEquipmentPage({super.key});

  @override
  State<AddEquipmentPage> createState() => _AddEquipmentPageState();
}

class _AddEquipmentPageState extends State<AddEquipmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _locCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  bool _saving = false;

  String _type = 'wheelchair';
  String _condition = 'good';
  String _availability = 'available';
  DateTime? _maintenanceUntil;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _locCtrl.dispose();
    _priceCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final price = _priceCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_priceCtrl.text);
    final imageUrl = _imageCtrl.text.trim();

    await CareCenterRepository.addEquipment(
      name: _nameCtrl.text.trim(),
      type: _type,
      description: _descCtrl.text.trim(),
      condition: _condition,
      quantityTotal: qty,
      location: _locCtrl.text.trim(),
      rentalPricePerDay: price,
      images: imageUrl.isNotEmpty ? [imageUrl] : [],
      isDonatedItem: false,
      availabilityStatus: _availability,
      maintenanceUntil: _availability == 'maintenance'
          ? _maintenanceUntil
          : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ToastService.showSuccess(context, 'Success', 'Equipment added');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add equipment')),
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
                        labelText: 'Image URL',
                        prefixIcon: Icon(Icons.link_rounded),
                        hintText: 'https://example.com/image.jpg',
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
                        DropdownMenuItem(
                          value: 'walker',
                          child: Text('Walker'),
                        ),
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
                      onChanged: (v) =>
                          setState(() => _type = v ?? 'wheelchair'),
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
                      onChanged: (v) =>
                          setState(() => _condition = v ?? 'good'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _availability,
                      decoration: const InputDecoration(
                        labelText: 'Availability status',
                        prefixIcon: Icon(Icons.info_outline_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'available',
                          child: Text('Available'),
                        ),
                        DropdownMenuItem(
                          value: 'rented',
                          child: Text('Rented'),
                        ),
                        DropdownMenuItem(
                          value: 'maintenance',
                          child: Text('Maintenance'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _availability = v ?? 'available'),
                    ),
                    if (_availability == 'maintenance') ...[
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.build_circle_rounded),
                        title: Text(
                          _maintenanceUntil == null
                              ? 'Maintenance until not set'
                              : 'Until: ${_maintenanceUntil!.toLocal().toString().split(' ').first}',
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setState(() => _maintenanceUntil = picked);
                            }
                          },
                          child: const Text('Set'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.description_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        prefixIcon: Icon(Icons.countertops_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rental price per day (optional)',
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save'),
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
