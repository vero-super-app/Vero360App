import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accommodation_offers.dart';
import 'package:vero360_app/widgets/merchant_commission_guide.dart';

/// Host adds room types and conference halls, each with a photo.
class PropertyOffersEditor extends StatelessWidget {
  static const Color _orange = Color(0xFFFF8A00);
  static const Color _navy = Color(0xFF16284C);

  final List<AccommodationRoomOffer> rooms;
  final List<AccommodationConferenceOffer> conferences;
  final ValueChanged<List<AccommodationRoomOffer>> onRoomsChanged;
  final ValueChanged<List<AccommodationConferenceOffer>> onConferencesChanged;

  const PropertyOffersEditor({
    super.key,
    required this.rooms,
    required this.conferences,
    required this.onRoomsChanged,
    required this.onConferencesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        _section(
          context,
          title: 'Rooms',
          hint: 'Up to 5 photos, a name, and a price for each room.',
          emptyLabel: 'Add room',
          onAdd: () => _addRoom(context),
          children: [
            for (var i = 0; i < rooms.length; i++)
              _thumb(
                bytes: rooms[i].imageBytes,
                url: rooms[i].imageUrl,
                label: rooms[i].name,
                onRemove: () {
                  final next = List<AccommodationRoomOffer>.from(rooms)
                    ..removeAt(i);
                  onRoomsChanged(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 18),
        _section(
          context,
          title: 'Conferences',
          hint: 'Up to 5 photos and a price for each hall.',
          emptyLabel: 'Add conference',
          onAdd: () => _addConference(context),
          children: [
            for (var i = 0; i < conferences.length; i++)
              _thumb(
                bytes: conferences[i].imageBytes,
                url: conferences[i].imageUrl,
                label: conferences[i].name,
                onRemove: () {
                  final next =
                      List<AccommodationConferenceOffer>.from(conferences)
                        ..removeAt(i);
                  onConferencesChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String hint,
    required String emptyLabel,
    required VoidCallback onAdd,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: _navy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        if (children.isNotEmpty)
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        if (children.isNotEmpty) const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(emptyLabel),
          style: TextButton.styleFrom(foregroundColor: _orange),
        ),
      ],
    );
  }

  Widget _thumb({
    required Uint8List? bytes,
    required String? url,
    required String label,
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      width: 84,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 84,
                  height: 64,
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.cover)
                      : (url ?? '').trim().isEmpty
                          ? ColoredBox(
                              color: const Color(0xFFF1F3F7),
                              child: Icon(
                                Icons.image_outlined,
                                color: Colors.grey.shade400,
                              ),
                            )
                          : Image.network(url!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addRoom(BuildContext context) async {
    final draft = await Navigator.of(context).push<_OfferDraft>(
      MaterialPageRoute(
        builder: (_) => const _OfferComposerPage(kind: _OfferKind.room),
      ),
    );
    if (draft == null) return;
    onRoomsChanged([
      ...rooms,
      AccommodationRoomOffer(
        name: draft.name,
        price: draft.price,
        quantity: draft.extra < 1 ? 1 : draft.extra,
        localImages: draft.photos,
        localFilenames: draft.filenames,
      ),
    ]);
  }

  Future<void> _addConference(BuildContext context) async {
    final draft = await Navigator.of(context).push<_OfferDraft>(
      MaterialPageRoute(
        builder: (_) => const _OfferComposerPage(kind: _OfferKind.conference),
      ),
    );
    if (draft == null) return;
    onConferencesChanged([
      ...conferences,
      AccommodationConferenceOffer(
        name: draft.name,
        price: draft.price,
        capacity: draft.extra < 0 ? 0 : draft.extra,
        localImages: draft.photos,
        localFilenames: draft.filenames,
      ),
    ]);
  }
}

enum _OfferKind { room, conference }

class _OfferDraft {
  final String name;
  final num price;
  final int extra;
  final List<Uint8List> photos;
  final List<String> filenames;

  const _OfferDraft({
    required this.name,
    required this.price,
    required this.extra,
    required this.photos,
    required this.filenames,
  });
}

class _OfferComposerPage extends StatefulWidget {
  final _OfferKind kind;

  const _OfferComposerPage({required this.kind});

  @override
  State<_OfferComposerPage> createState() => _OfferComposerPageState();
}

class _OfferComposerPageState extends State<_OfferComposerPage> {
  static const Color _orange = Color(0xFFFF8A00);
  static const Color _navy = Color(0xFF16284C);

  final _picker = ImagePicker();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _extra = TextEditingController();
  final List<Uint8List> _photos = [];
  final List<String> _filenames = [];

  bool get _isRoom => widget.kind == _OfferKind.room;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _extra.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_photos.length >= kAccommodationOfferPhotoLimit) {
      _toast('You can add up to $kAccommodationOfferPhotoLimit photos');
      return;
    }
    if (source == ImageSource.gallery) {
      final remaining = kAccommodationOfferPhotoLimit - _photos.length;
      final files = await _picker.pickMultiImage(
        imageQuality: 72,
        maxWidth: 1280,
      );
      if (!mounted || files.isEmpty) return;
      final batch = <Uint8List>[];
      final names = <String>[];
      for (final file in files.take(remaining)) {
        batch.add(await file.readAsBytes());
        names.add(file.name);
      }
      if (!mounted || batch.isEmpty) return;
      setState(() {
        _photos.addAll(batch);
        _filenames.addAll(names);
      });
      return;
    }
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 1280,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photos.add(bytes);
      _filenames.add(file.name);
    });
  }

  void _save() {
    final name = _name.text.trim();
    final price = num.tryParse(_price.text.trim()) ?? 0;
    final extra = int.tryParse(_extra.text.trim()) ?? (_isRoom ? 0 : 0);
    if (_photos.isEmpty) {
      _toast('Add at least one photo');
      return;
    }
    if (name.isEmpty || price <= 0) {
      _toast('Enter a name and a price');
      return;
    }
    if (_isRoom && extra < 1) {
      _toast('Enter how many rooms');
      return;
    }
    Navigator.pop(
      context,
      _OfferDraft(
        name: name,
        price: price,
        extra: extra,
        photos: List<Uint8List>.from(_photos),
        filenames: List<String>.from(_filenames),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isRoom ? 'Add room' : 'Add conference'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text(
            'Photos ${_photos.length}/$kAccommodationOfferPhotoLimit',
            style: const TextStyle(fontWeight: FontWeight.w800, color: _navy),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            _photos[i],
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _photos.removeAt(i);
                              if (i < _filenames.length) _filenames.removeAt(i);
                            }),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_photos.length < kAccommodationOfferPhotoLimit)
                  GestureDetector(
                    onTap: () => _pick(ImageSource.gallery),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, color: _orange),
                          SizedBox(height: 4),
                          Text(
                            'Add',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
              TextButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: _isRoom ? 'Room name' : 'Hall name',
              hintText: _isRoom ? 'e.g. Executive' : 'e.g. Main hall',
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Price (MWK)',
              hintText: 'e.g. 100000',
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _price,
            builder: (context, value, _) => MerchantCommissionGuide.priceNote(
              context,
              priceText: value.text,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _extra,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _isRoom ? 'How many of this room' : 'People it holds',
              hintText: _isRoom ? 'e.g. 4' : 'Optional',
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
