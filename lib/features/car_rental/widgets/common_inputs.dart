import 'package:flutter/material.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_design_system.dart';

/// Text input field with consistent styling
class CommonTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final bool obscureText;
  final int maxLines;
  final int minLines;
  final int? maxLength;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final VoidCallback? onSuffixIconPressed;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final String? errorText;
  final bool isEnabled;
  final bool isRequired;
  final String? helperText;

  const CommonTextField({
    Key? key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconPressed,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.errorText,
    this.isEnabled = true,
    this.isRequired = false,
    this.helperText,
  }) : super(key: key);

  @override
  State<CommonTextField> createState() => _CommonTextFieldState();
}

class _CommonTextFieldState extends State<CommonTextField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      obscureText: _obscureText,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      enabled: widget.isEnabled,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      decoration: CarRentalDesignSystem.inputDecoration(
        labelText: widget.isRequired ? '${widget.label}*' : widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility_off : Icons.visibility,
                  color: CarRentalColors.textTertiary,
                ),
                onPressed: () {
                  setState(() => _obscureText = !_obscureText);
                },
              )
            : widget.suffixIcon != null
                ? GestureDetector(
                    onTap: widget.onSuffixIconPressed,
                    child: widget.suffixIcon,
                  )
                : null,
        errorText: widget.errorText,
      ),
      style: CarRentalDesignSystem.bodyMedium(context),
      cursorColor: CarRentalColors.primary,
    );
  }
}

/// Dropdown field with consistent styling
class CommonDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;
  final bool isRequired;
  final bool isEnabled;
  final Widget? prefixIcon;
  final String? hint;

  const CommonDropdown({
    Key? key,
    required this.label,
    this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.isRequired = false,
    this.isEnabled = true,
    this.prefixIcon,
    this.hint,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: isEnabled ? onChanged : null,
      validator: validator,
      decoration: CarRentalDesignSystem.inputDecoration(
        labelText: isRequired ? '$label*' : label,
        hintText: hint,
        prefixIcon: prefixIcon,
      ),
      style: CarRentalDesignSystem.bodyMedium(context),
      isExpanded: true,
      menuMaxHeight: 300,
    );
  }
}

/// Date picker field
class CommonDateField extends StatefulWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onDateChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool isRequired;
  final String? Function(DateTime?)? validator;

  const CommonDateField({
    Key? key,
    required this.label,
    this.value,
    required this.onDateChanged,
    this.firstDate,
    this.lastDate,
    this.isRequired = false,
    this.validator,
  }) : super(key: key);

  @override
  State<CommonDateField> createState() => _CommonDateFieldState();
}

class _CommonDateFieldState extends State<CommonDateField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value != null ? _formatDate(widget.value!) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? DateTime.now(),
      firstDate: widget.firstDate ?? DateTime(2000),
      lastDate: widget.lastDate ?? DateTime(2100),
    );

    if (picked != null) {
      widget.onDateChanged(picked);
      setState(() {
        _controller.text = _formatDate(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      onTap: _selectDate,
      validator: (value) {
        if (widget.isRequired && (value == null || value.isEmpty)) {
          return '${widget.label} is required';
        }
        return null;
      },
      decoration: CarRentalDesignSystem.inputDecoration(
        labelText: widget.isRequired ? '${widget.label}*' : widget.label,
        prefixIcon: const Icon(Icons.calendar_today),
      ),
      style: CarRentalDesignSystem.bodyMedium(context),
    );
  }
}

/// Checkbox field
class CommonCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final bool isRequired;

  const CommonCheckbox({
    Key? key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.isRequired = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: CarRentalColors.primary,
          side: BorderSide(
            color: CarRentalColors.grey300,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CarRentalBorderRadius.xs),
          ),
        ),
        const SizedBox(width: CarRentalSpacing.sm),
        Expanded(
          child: Text(
            isRequired ? '$label*' : label,
            style: CarRentalDesignSystem.bodyMedium(context),
          ),
        ),
      ],
    );
  }
}

/// Radio button group
class CommonRadioGroup<T> extends StatelessWidget {
  final T value;
  final List<RadioOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String? label;
  final Axis direction;

  const CommonRadioGroup({
    Key? key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.direction = Axis.vertical,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: CarRentalDesignSystem.subtitle1(context),
          ),
          const SizedBox(height: CarRentalSpacing.sm),
        ],
        direction == Axis.vertical
            ? Column(
                children: _buildOptions(context),
              )
            : Row(
                children: _buildOptions(context),
              ),
      ],
    );
  }

  List<Widget> _buildOptions(BuildContext context) {
    return options.map((option) {
      return Row(
        children: [
          Radio<T>(
            value: option.value,
            groupValue: value,
            onChanged: onChanged,
            activeColor: CarRentalColors.primary,
          ),
          const SizedBox(width: CarRentalSpacing.sm),
          Expanded(
            child: Text(
              option.label,
              style: CarRentalDesignSystem.bodyMedium(context),
            ),
          ),
        ],
      );
    }).toList();
  }
}

class RadioOption<T> {
  final T value;
  final String label;

  RadioOption({
    required this.value,
    required this.label,
  });
}
