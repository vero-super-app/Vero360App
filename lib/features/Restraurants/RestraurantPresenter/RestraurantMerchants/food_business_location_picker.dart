import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/place_prediction_model.dart';
import 'package:vero360_app/GernalServices/google_places_service.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/map_location_picker_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Merchant shop location: type an address, search suggestions, or pin on the map.
class FoodBusinessLocationPickerPage extends ConsumerStatefulWidget {
  const FoodBusinessLocationPickerPage({
    super.key,
    this.initialAddress,
    this.initialLatitude,
    this.initialLongitude,
    this.title = 'Business location',
    this.hint =
        'Type your address, search for a place, or pin it on the map.',
    this.emptyAddressMessage = 'Type your business address first.',
    this.mapPinHintSubtitle =
        'Drop a pin exactly where your business is.',
  });

  final String? initialAddress;
  final double? initialLatitude;
  final double? initialLongitude;
  final String title;
  final String hint;
  final String emptyAddressMessage;
  final String mapPinHintSubtitle;

  @override
  ConsumerState<FoodBusinessLocationPickerPage> createState() =>
      _FoodBusinessLocationPickerPageState();
}

class _FoodBusinessLocationPickerPageState
    extends ConsumerState<FoodBusinessLocationPickerPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  String? _loadingPlaceId;
  bool _savingTyped = false;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialAddress ?? '').trim();
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _query = initial;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _popPlace(Place place) {
    if (!mounted) return;
    Navigator.of(context).pop(place);
  }

  Future<void> _pickPrediction(PlacePrediction prediction) async {
    if (_loadingPlaceId != null) return;
    final trackingId = prediction.placeId.isNotEmpty
        ? prediction.placeId
        : prediction.fullText;
    setState(() => _loadingPlaceId = trackingId);
    try {
      final placesService = ref.read(googlePlacesServiceProvider);
      if (placesService == null) {
        throw Exception('Places is unavailable');
      }
      final place = await placesService
          .resolvePrediction(prediction)
          .timeout(const Duration(seconds: 20));
      _popPlace(place);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FoodLocation] resolve failed: $e\n$st');
      }
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Could not use that place. Try another result or pin on the map.',
          isSuccess: false,
          errorMessage: 'Location failed',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPlaceId = null);
    }
  }

  Future<void> _saveTypedAddress() async {
    final typed = _controller.text.trim();
    if (typed.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        widget.emptyAddressMessage,
        isSuccess: false,
        errorMessage: 'Address required',
      );
      return;
    }
    if (_savingTyped) return;
    setState(() => _savingTyped = true);
    try {
      final placesService = ref.read(googlePlacesServiceProvider);
      Place? geocoded;
      if (placesService != null) {
        try {
          geocoded = await placesService
              .geocodeAddress(typed)
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          if (kDebugMode) debugPrint('[FoodLocation] geocode typed: $e');
        }
      }

      if (geocoded != null &&
          (geocoded.latitude.abs() > 0.0001 ||
              geocoded.longitude.abs() > 0.0001)) {
        var label = typed;
        final name = geocoded.name.trim();
        final address = geocoded.address.trim();
        if (placesService != null &&
            (GooglePlacesService.isPlusCodeLabel(typed) ||
                GooglePlacesService.isPlusCodeLabel(name) ||
                GooglePlacesService.isPlusCodeLabel(address))) {
          final decoded = await placesService.lookupStreetName(
            typed,
            biasLat: geocoded.latitude,
            biasLng: geocoded.longitude,
          );
          if (decoded != null) {
            final decodedName = decoded.name.trim();
            final decodedAddr = decoded.address.trim();
            if (decodedName.isNotEmpty &&
                !GooglePlacesService.isPlusCodeLabel(decodedName)) {
              label = decodedAddr.isNotEmpty &&
                      !GooglePlacesService.isPlusCodeLabel(decodedAddr)
                  ? decodedAddr
                  : decodedName;
            } else if (decodedAddr.isNotEmpty &&
                !GooglePlacesService.isPlusCodeLabel(decodedAddr)) {
              label = decodedAddr;
            }
          } else {
            final rev = await placesService.reverseGeocode(
              latitude: geocoded.latitude,
              longitude: geocoded.longitude,
            );
            if (rev != null) {
              final revName = rev.name.trim();
              final revAddr = rev.address.trim();
              if (revName.isNotEmpty &&
                  !GooglePlacesService.isPlusCodeLabel(revName)) {
                label = revAddr.isNotEmpty &&
                        !GooglePlacesService.isPlusCodeLabel(revAddr)
                    ? revAddr
                    : revName;
              } else if (revAddr.isNotEmpty &&
                  !GooglePlacesService.isPlusCodeLabel(revAddr)) {
                label = revAddr;
              }
            }
          }
        } else if (name.isNotEmpty &&
            !GooglePlacesService.isPlusCodeLabel(name) &&
            typed.length < 8) {
          // Short typed query — prefer the resolved street label.
          label = address.isNotEmpty &&
                  !GooglePlacesService.isPlusCodeLabel(address)
              ? address
              : name;
        }

        _popPlace(
          Place(
            id: geocoded.id,
            name: label.split(',').first.trim().isEmpty
                ? geocoded.name
                : label.split(',').first.trim(),
            address: label,
            latitude: geocoded.latitude,
            longitude: geocoded.longitude,
            type: PlaceType.RECENT,
          ),
        );
        return;
      }

      final lat = widget.initialLatitude;
      final lng = widget.initialLongitude;
      if (lat != null && lng != null) {
        _popPlace(
          Place(
            id: 'typed_${lat}_$lng',
            name: typed.split(',').first.trim(),
            address: typed,
            latitude: lat,
            longitude: lng,
            type: PlaceType.RECENT,
          ),
        );
        return;
      }

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not find that address on the map. Pick a search result or pin the location.',
        isSuccess: false,
        errorMessage: 'Need map pin',
      );
    } finally {
      if (mounted) setState(() => _savingTyped = false);
    }
  }

  Future<void> _openMapPin() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          selectAsDropoff: false,
          initialLatitude: widget.initialLatitude,
          initialLongitude: widget.initialLongitude,
        ),
      ),
    );
    if (place != null) _popPlace(place);
  }

  @override
  Widget build(BuildContext context) {
    final searchResults =
        ref.watch(serpapiPlacesAutocompleteProvider(_query.trim()));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                widget.hint,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                elevation: 1,
                shadowColor: Colors.black26,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'e.g. Area 18, Lilongwe',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: _brandOrange),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) => unawaited(_saveTypedAddress()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_savingTyped || _loadingPlaceId != null)
                          ? null
                          : () => unawaited(_openMapPin()),
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('Pin on map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brandNavy,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_savingTyped ||
                              _loadingPlaceId != null ||
                              _query.trim().isEmpty)
                          ? null
                          : () => unawaited(_saveTypedAddress()),
                      icon: _savingTyped
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_savingTyped ? 'Saving…' : 'Use address'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _query.trim().length < 3
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _hintTile(
                          icon: Icons.keyboard_rounded,
                          title: 'Type your location',
                          subtitle:
                              'Enter a street, area, or landmark, then tap Use address.',
                        ),
                        const SizedBox(height: 10),
                        _hintTile(
                          icon: Icons.search_rounded,
                          title: 'Search',
                          subtitle:
                              'Keep typing to see place suggestions, then tap one.',
                        ),
                        const SizedBox(height: 10),
                        _hintTile(
                          icon: Icons.location_on_rounded,
                          title: 'Pin on map',
                          subtitle: widget.mapPinHintSubtitle,
                          onTap: () => unawaited(_openMapPin()),
                        ),
                      ],
                    )
                  : searchResults.when(
                      data: (predictions) {
                        if (predictions.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No search results. Use address as typed, or pin on the map.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: predictions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final p = predictions[index];
                            final rowId = p.placeId.isNotEmpty
                                ? p.placeId
                                : p.fullText;
                            final loading = _loadingPlaceId == rowId;
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      _brandOrange.withValues(alpha: 0.12),
                                  child: loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _brandOrange,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.place_outlined,
                                          color: _brandOrange,
                                        ),
                                ),
                                title: Text(
                                  p.mainText.isNotEmpty
                                      ? p.mainText
                                      : p.fullText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _brandNavy,
                                  ),
                                ),
                                subtitle: Text(
                                  p.secondaryText.isNotEmpty
                                      ? p.secondaryText
                                      : p.fullText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                enabled:
                                    !loading && _loadingPlaceId == null,
                                onTap: loading
                                    ? null
                                    : () => unawaited(_pickPrediction(p)),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: _brandOrange),
                      ),
                      error: (_, __) => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Search unavailable. Type an address or pin on the map.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _brandOrange.withValues(alpha: 0.12),
                child: Icon(icon, color: _brandOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _brandNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
