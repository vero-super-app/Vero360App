import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
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
    return _controllers.putIfAbsent(
      requirement,
      () => TextEditingController(),
    );
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

    final result =
        await ref.read(verificationSubmitProvider.notifier).submit(evidence);
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
        error: (error, _) => CarHireErrorState(
          error: error,
          onRetry: _refresh,
        ),
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
              const SizedBox(height: 12),
              if (verification.status == VerificationState.verified)
                _verifiedNote()
              else if (verification.requirements.isEmpty)
                const _Panel(
                  child: Text(
                    'Vero360 has not listed any document requirements for '
                    'your account right now. If support asked you for a '
                    'document, contact them to have the requirement added.',
                    style: TextStyle(
                      color: CarRentalColors.body,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                )
              else
                _submissionCard(verification.requirements, mutation),
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
          if (verification.requirements.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Required documents',
              style: TextStyle(
                color: CarRentalColors.title,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            ...verification.requirements.map(
              (requirement) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.description_outlined,
                        size: 15,
                        color: CarRentalColors.brandOrange,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        requirement,
                        style: const TextStyle(
                          color: CarRentalColors.title,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _verifiedNote() {
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: CarRentalColors.success,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Your driver verification is complete. You do not need to '
              'submit anything else unless Vero360 support asks you to renew '
              'an expiring document.',
              style: TextStyle(
                color: CarRentalColors.body,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
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
          const SizedBox(height: 6),
          const Text(
            'Upload is handled by Vero360 support in this version of the app. '
            'Enter the document reference or upload ID support gave you for '
            'each requirement. Files themselves are stored by Vero360 '
            'support — this form sends only the reference.',
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
                helper: 'Provided by Vero360 support',
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
          if (!_hasAnyReference(requirements))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Enter at least one document reference to submit.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CarRentalColors.grey,
                  fontSize: 10.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusCopy(VerificationState status) {
    switch (status) {
      case VerificationState.notStarted:
        return 'Vero360 has not received your driver documents yet. Submit '
            'the references support requested to start the review.';
      case VerificationState.submitted:
        return 'Your documents have been submitted. Vero360 support will '
            'review them and update this status.';
      case VerificationState.underReview:
        return 'Vero360 support is reviewing your documents. You can submit '
            'additional references if support asked for them.';
      case VerificationState.verified:
        return 'Vero360 has verified your driver documents.';
      case VerificationState.rejected:
        return 'Vero360 could not verify the documents submitted. Check the '
            'next step below and submit a new reference.';
      case VerificationState.expired:
        return 'Your verification has expired. Submit a current document '
            'reference to renew it.';
      case VerificationState.suspended:
        return 'Driver verification is suspended. Contact Vero360 support '
            'before booking another vehicle.';
      case VerificationState.unknown:
        return 'We could not read your verification status. Refresh to try '
            'again, or contact Vero360 support.';
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
