import 'package:flutter/material.dart';
import '../../services/repository.dart';
import '../../ui/custom_toast.dart';

class DonationFormPage extends StatefulWidget {
  final String? donorId;
  const DonationFormPage({super.key, required this.donorId});

  @override
  State<DonationFormPage> createState() => _DonationFormPageState();
}

class _DonationFormPageState extends State<DonationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _donorNameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _imageCtrl = TextEditingController();
  String _itemType = 'wheelchair';
  String _condition = 'good';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.donorId == null) {
      _donorNameCtrl.text = 'Guest';
    }
  }

  @override
  void dispose() {
    _donorNameCtrl.dispose();
    _contactCtrl.dispose();
    _qtyCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final imageUrl = _imageCtrl.text.trim();

    await CareCenterRepository.addDonation(
      donorId: widget.donorId,
      donorName: _donorNameCtrl.text.trim(),
      donorContact: _contactCtrl.text.trim(),
      itemType: _itemType,
      condition: _condition,
      quantity: qty,
      description: '',
      photos: imageUrl.isNotEmpty ? [imageUrl] : [],
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ToastService.showSuccess(context, 'Success', 'Donation submitted');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offer a donation')),
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
                      controller: _donorNameCtrl,
                      readOnly: widget.donorId == null,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _contactCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contact info',
                        prefixIcon: Icon(Icons.contact_phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _itemType,
                      decoration: const InputDecoration(
                        labelText: 'Item type',
                        prefixIcon: Icon(Icons.medical_services_rounded),
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
                          setState(() => _itemType = v ?? 'wheelchair'),
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
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        prefixIcon: Icon(Icons.countertops_rounded),
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
                            : const Text('Submit donation'),
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
