import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

const Map<String, String> _docTypeLabels = {
  'license': 'Driving License',
  'insurance': 'Vehicle Insurance',
  'registration': 'Vehicle Registration',
  'background_check': 'Background Check',
  'profile_photo': 'Profile Photo',
};

class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  List<Map<String, dynamic>> _documents = [];
  List<String> _requiredDocTypes = [];
  String? _kycStatus;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await ApiService.getDriverDocuments();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _documents = List<Map<String, dynamic>>.from(result['documents']);
        _requiredDocTypes = List<String>.from(result['requiredDocTypes']);
        _kycStatus = result['kycStatus'] as String?;
      } else {
        _error = result['error'];
      }
    });
  }

  Map<String, dynamic>? _latestFor(String docType) {
    final matches = _documents.where((d) => d['doc_type'] == docType).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => (b['uploaded_at'] as String).compareTo(a['uploaded_at'] as String));
    return matches.first;
  }

  void _openSubmitSheet(String docType, Map<String, dynamic>? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => _SubmitDocumentSheet(
        docType: docType,
        existing: existing,
        onSubmitted: _load,
      ),
    );
  }

  String _kycBannerText(String? status) {
    switch (status) {
      case 'approved':
        return 'Your documents are verified. You\'re all set.';
      case 'in_review':
        return 'Your documents are being reviewed.';
      case 'rejected':
        return 'One or more documents were rejected — please resubmit.';
      case 'pending':
        return 'Your KYC review is pending.';
      default:
        return 'Submit all required documents to get verified.';
    }
  }

  Color _kycBannerColor(String? status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return const Color(0xFFB45309);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('KYC Documents', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: _kycBannerColor(_kycStatus).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_kycBannerText(_kycStatus), style: TextStyle(color: _kycBannerColor(_kycStatus), fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ..._requiredDocTypes.map((docType) {
                    final latest = _latestFor(docType);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _DocumentCard(
                        docType: docType,
                        document: latest,
                        onTap: () => _openSubmitSheet(docType, latest),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final String docType;
  final Map<String, dynamic>? document;
  final VoidCallback onTap;

  const _DocumentCard({required this.docType, required this.document, required this.onTap});

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return const Color(0xFFB45309);
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'pending':
        return 'Pending review';
      default:
        return 'Not submitted';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = document?['verification_status'] as String?;
    final rejectionReason = document?['rejection_reason'] as String?;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(
              status == 'approved' ? Icons.check_circle : Icons.description_outlined,
              color: status == 'approved' ? AppColors.success : AppColors.textSecondary,
              size: 26,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_docTypeLabels[docType] ?? docType, style: AppTextStyles.label),
                  const SizedBox(height: 2),
                  Text(
                    status == 'rejected' && rejectionReason != null ? rejectionReason : _statusLabel(status),
                    style: AppTextStyles.helper.copyWith(color: status == 'rejected' ? AppColors.error : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: status == null ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusLabel(status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: status == null ? AppColors.textSecondary : _statusColor(status)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitDocumentSheet extends StatefulWidget {
  final String docType;
  final Map<String, dynamic>? existing;
  final VoidCallback onSubmitted;

  const _SubmitDocumentSheet({required this.docType, required this.existing, required this.onSubmitted});

  @override
  State<_SubmitDocumentSheet> createState() => _SubmitDocumentSheetState();
}

class _SubmitDocumentSheetState extends State<_SubmitDocumentSheet> {
  final _urlController = TextEditingController();
  DateTime? _expiresAt;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'A document URL is required');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ApiService.submitDriverDocument(
      docType: widget.docType,
      url: url,
      expiresAt: _expiresAt != null
          ? '${_expiresAt!.year.toString().padLeft(4, '0')}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}'
          : null,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result['success']) {
      widget.onSubmitted();
      Navigator.pop(context);
    } else {
      setState(() => _error = result['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _docTypeLabels[widget.docType] ?? widget.docType;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Submit $label', style: AppTextStyles.heading1.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Upload your document to any file host and paste the link below.',
              style: AppTextStyles.helper,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'Document URL', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: _pickExpiry,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Expiry date (optional)', border: OutlineInputBorder()),
                child: Text(
                  _expiresAt != null
                      ? '${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTextStyles.errorText),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Submit for Review', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
