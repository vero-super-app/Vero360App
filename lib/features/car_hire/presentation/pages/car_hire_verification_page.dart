import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

class CarHireVerificationPage extends ConsumerStatefulWidget {
  const CarHireVerificationPage({super.key});

  @override
  ConsumerState<CarHireVerificationPage> createState() =>
      _CarHireVerificationPageState();
}

class _CarHireVerificationPageState
    extends ConsumerState<CarHireVerificationPage> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  TextEditingController _controllerFor(String requirement) {
    return _controllers.putIfAbsent(requirement, () => TextEditingController());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(verificationRequirementsProvider);
    try {
      await ref.read(verificationRequirementsProvider.future);
    } catch (_) {
      // The provider renders the error state.
    }
  }

  bool _hasAnyReference(List<String> requirements) {
    for (final requirement in requirements) {
      if (_controllerFor(requirement).text.trim().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _submit(List<String> requirements) async {
    FocusScope.of(context).unfocus();
    final evidence = <VerificationEvidence>[];
    for (final requirement in requirements) {
      final reference = _controllerFor(requirement).text.trim();
      if (reference.isEmpty) continue;
      evidence.add(
        VerificationEvidence(
          requirement: requirement,
          fileReference: reference,
        ),
      );
    }
    if (evidence.isEmpty) return;

    final result = await ref
        .read(verificationSubmitProvider.notifier)
        .submit(evidence);
    if (!mounted) return;

    if (result != null) {
      for (final controller in _controllers.values) {
        controller.clear();
      }
      setState(() {});
      ToastHelper.showToast(
        context,
        'Verification documents submitted. Vero360 support will review them.',
      );
      return;
    }

    final error = ref.read(verificationSubmitProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(UserFacingError.sanitize(error.message)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(verificationRequirementsProvider);
    final mutation = ref.watch(verificationSubmitProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Driver verification',
        actions: [
          CarHireIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: _refresh,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: async.when(
        loading: () => const CarHireLoadingState(
          message: 'Loading verification requirements…',
        ),
        error: (error, _) => CarHireErrorState(error: error, onRetry: _refresh),
        data: (verification) => RefreshIndicator(
          color: CarRentalColors.brandOrange,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _statusCard(verification),
              if (mutation.hasError) ...[
                const SizedBox(height: 12),
                CarHireInlineError(message: mutation.error!.message),
              ],
              if (verification.status != VerificationState.verified &&
                  verification.requirements.isNotEmpty) ...[
                const SizedBox(height: 12),
                _submissionCard(verification.requirements, mutation),
              ],
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => CarHireRoutes.openTerms(context),
                  style: TextButton.styleFrom(
                    foregroundColor: CarRentalColors.grey,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  child: const Text('How we handle your documents'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(CarHireVerification verification) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Verification status',
                  style: TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: CarHireStatusBadge.verification(verification.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _statusCopy(verification.status),
            style: const TextStyle(
              color: CarRentalColors.body,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (verification.nextAction != null &&
              verification.nextAction!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CarRentalColors.brandOrangePale,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: CarRentalColors.brandOrange,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Next step: ${verification.nextAction!.trim()}',
                      style: const TextStyle(
                        color: CarRentalColors.body,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _submissionCard(
    List<String> requirements,
    CarHireMutationState mutation,
  ) {
    final canSubmit = _hasAnyReference(requirements) && !mutation.submitting;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Submit a document reference',
            style: TextStyle(
              color: CarRentalColors.title,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter the reference support gave you for each document.',
            style: TextStyle(
              color: CarRentalColors.body,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          for (final requirement in requirements) ...[
            TextField(
              controller: _controllerFor(requirement),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: carHireInputDecoration(
                label: requirement,
                hint: 'Document reference / upload ID',
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: canSubmit ? () => _submit(requirements) : null,
            icon: mutation.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(
              mutation.submitting
                  ? 'Submitting references…'
                  : 'Submit for review',
            ),
            style: carHirePrimaryButton(),
          ),
        ],
      ),
    );
  }

  String _statusCopy(VerificationState status) {
    switch (status) {
      case VerificationState.notStarted:
        return 'Submit your documents to start the review.';
      case VerificationState.submitted:
        return 'Submitted. Support will review your documents.';
      case VerificationState.underReview:
        return 'Support is reviewing your documents.';
      case VerificationState.verified:
        return 'You are verified to rent.';
      case VerificationState.rejected:
        return 'We could not verify your documents. Submit a new reference.';
      case VerificationState.expired:
        return 'Your verification expired. Submit a current document.';
      case VerificationState.suspended:
        return 'Verification is suspended. Contact support before booking.';
      case VerificationState.unknown:
        return 'We could not load your status. Pull down to refresh.';
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(padding: const EdgeInsets.all(16), child: child);
  }
}
