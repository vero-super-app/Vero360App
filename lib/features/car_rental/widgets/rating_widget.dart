import 'package:flutter/material.dart';

class RatingWidget extends StatelessWidget {
  final double rating;
  final int reviewCount;
  final VoidCallback? onTap;
  final bool showLabel;

  const RatingWidget({
    Key? key,
    required this.rating,
    required this.reviewCount,
    this.onTap,
    this.showLabel = true,
  }) : super(key: key);

  Widget _buildStars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Icon(
          index < rating.toInt() ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStars(),
              const SizedBox(width: 8),
              Text(
                rating.toStringAsFixed(1),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(
              '($reviewCount ${reviewCount == 1 ? 'review' : 'reviews'})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class StarRatingInput extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double> onRatingChanged;
  final int starCount;
  final double starSize;

  const StarRatingInput({
    Key? key,
    required this.initialRating,
    required this.onRatingChanged,
    this.starCount = 5,
    this.starSize = 32,
  }) : super(key: key);

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  late double _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        widget.starCount,
        (index) => GestureDetector(
          onTap: () {
            setState(() {
              _rating = (index + 1).toDouble();
            });
            widget.onRatingChanged(_rating);
          },
          child: Icon(
            index < _rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: widget.starSize,
          ),
        ),
      ),
    );
  }
}
