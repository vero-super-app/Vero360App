import 'package:flutter/material.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';

class TripSelectorCard extends StatelessWidget {
  final String currentLocation;
  final Place? selectedDropoffPlace;
  final VoidCallback onSelectDropoff;

  const TripSelectorCard({
    required this.currentLocation,
    this.selectedDropoffPlace,
    required this.onSelectDropoff,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Pickup location
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pickup',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentLocation,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Connector line
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Column(
                    children: [
                      Container(
                        width: 2,
                        height: 8,
                        color: Colors.grey[300],
                      ),
                      Container(
                        width: 2,
                        height: 8,
                        color: Colors.grey[300],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // Dropoff location or input
          GestureDetector(
            onTap: onSelectDropoff,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8A00).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: selectedDropoffPlace != null
                        ? const Color(0xFFFF8A00)
                        : Colors.grey[400],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dropoff',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedDropoffPlace?.name ?? 'Where to?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selectedDropoffPlace != null
                              ? Colors.black
                              : Colors.grey[500],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selectedDropoffPlace == null)
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: Colors.grey[400],
                  )
                else
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: const Color(0xFFFF8A00),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
