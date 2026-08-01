import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Full-screen map to pick a destination by dragging / tapping.
class MapLocationPickerScreen extends ConsumerStatefulWidget {
  final PlaceType? saveAsType;

  /// When false, only returns the place without setting dropoff.
  final bool selectAsDropoff;

  const MapLocationPickerScreen({
    this.saveAsType,
    this.selectAsDropoff = true,
    super.key,
  });

  @override
  ConsumerState<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState
    extends ConsumerState<MapLocationPickerScreen> {
  GoogleMapController? _controller;
  LatLng? _selected;
  String _address = 'Move the map to choose a location';
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pos = ref.read(currentLocationProvider).maybeWhen(
            data: (p) => p,
            orElse: () => null,
          );
      if (pos != null) {
        setState(() {
          _selected = LatLng(pos.latitude, pos.longitude);
        });
        _resolveAddress(_selected!);
      }
    });
  }

  Future<void> _resolveAddress(LatLng latLng) async {
    setState(() {
      _selected = latLng;
      _resolving = true;
    });
    final address = await ref.read(placeServiceProvider).getAddressFromCoordinates(
          latLng.latitude,
          latLng.longitude,
        );
    if (!mounted) return;
    setState(() {
      _address = address ??
          '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
      _resolving = false;
    });
  }

  Future<void> _confirm() async {
    final latLng = _selected;
    if (latLng == null) return;

    final place = Place(
      id: 'map_${latLng.latitude}_${latLng.longitude}',
      name: widget.saveAsType == PlaceType.HOME
          ? 'Home'
          : widget.saveAsType == PlaceType.WORK
              ? 'Work'
              : (_address.split(',').first.trim().isEmpty
                  ? 'Pinned location'
                  : _address.split(',').first.trim()),
      address: _address,
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      type: widget.saveAsType ?? PlaceType.RECENT,
      isBookmarked: widget.saveAsType != null,
      savedAt: DateTime.now(),
    );

    if (widget.saveAsType == PlaceType.HOME ||
        widget.saveAsType == PlaceType.WORK) {
      await BookmarkedPlacesManager.setHomeOrWork(
        ref,
        place,
        widget.saveAsType!,
      );
      if (mounted) Navigator.pop(context, place);
      return;
    }

    if (widget.selectAsDropoff) {
      RecentPlacesManager.addPlace(ref, place);
      ref.read(selectedDropoffPlaceProvider.notifier).state = place;
    }
    if (mounted) Navigator.pop(context, place);
  }

  String get _title {
    switch (widget.saveAsType) {
      case PlaceType.HOME:
        return 'Set Home on map';
      case PlaceType.WORK:
        return 'Set Work on map';
      default:
        return 'Set on map';
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentLocationProvider);
    final initial = _selected ??
        current.maybeWhen(
          data: (p) => p != null ? LatLng(p.latitude, p.longitude) : null,
          orElse: () => null,
        ) ??
        const LatLng(-13.9626, 33.7741); // Lilongwe fallback

    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initial, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) => _controller = c,
            onCameraMove: (pos) => _selected = pos.target,
            onCameraIdle: () {
              if (_selected != null) _resolveAddress(_selected!);
            },
            onTap: (latLng) {
              _controller?.animateCamera(CameraUpdate.newLatLng(latLng));
              _resolveAddress(latLng);
            },
          ),
          // Center pin
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(
                  Icons.location_on,
                  size: 48,
                  color: RideShareColors.primary,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    color: RideShareColors.titleText,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Text(
                        _title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: RideShareColors.titleText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 140,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                icon: const Icon(Icons.my_location),
                color: RideShareColors.primary,
                onPressed: () {
                  current.whenData((pos) {
                    if (pos == null) return;
                    final target = LatLng(pos.latitude, pos.longitude);
                    _controller?.animateCamera(
                      CameraUpdate.newLatLngZoom(target, 16),
                    );
                    _resolveAddress(target);
                  });
                },
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place, color: RideShareColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _resolving
                              ? const Text(
                                  'Getting address…',
                                  style: TextStyle(
                                    color: RideShareColors.onSurfaceVariant,
                                  ),
                                )
                              : Text(
                                  _address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: RideShareColors.titleText,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _selected == null || _resolving
                            ? null
                            : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: RideShareColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text(
                          widget.saveAsType != null
                              ? 'Save location'
                              : 'Confirm destination',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
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
