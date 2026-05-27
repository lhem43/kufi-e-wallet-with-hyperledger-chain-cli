import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

/// Sub-screen: Trợ giúp — user can send help requests to admin.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendHelpRequest() async {
    final tr = AppLocalizations.pick;
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              vi: 'Vui lòng nhập đầy đủ tiêu đề và nội dung',
              en: 'Please enter both subject and message',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    // Simulate API call — in production this would call a real endpoint
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            vi: 'Đã gửi yêu cầu hỗ trợ thành công',
            en: 'Support request sent successfully',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final iconBg = isDark ? const Color(0xFF2A3344) : AppColors.violet100;
    final iconColor = isDark ? const Color(0xFFAEC0D9) : AppColors.violet600;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Trợ giúp', en: 'Help')),
      ),
      body: AppBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // FAQ section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.question_answer_outlined,
                              color: iconColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            tr(
                              vi: 'Câu hỏi thường gặp',
                              en: 'Frequently asked questions',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: titleColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _FaqTile(
                        question: tr(
                          vi: 'Chuyển tiền bao lâu đến tài khoản?',
                          en: 'How long does a transfer take?',
                        ),
                        answer: tr(
                          vi: 'Giao dịch thường đến ngay. Một số giao dịch có thể chậm vài giây.',
                          en: 'Transfers are usually instant. Some transactions may take a few extra seconds.',
                        ),
                        titleColor: titleColor,
                        subColor: subColor,
                        isDark: isDark,
                      ),
                      _FaqTile(
                        question: tr(
                          vi: 'Quên mã PIN?',
                          en: 'Forgot your PIN?',
                        ),
                        answer: tr(
                          vi: 'Đăng xuất và đăng nhập lại bằng mật khẩu, sau đó tạo PIN mới.',
                          en: 'Sign out and sign in again with your password, then create a new PIN.',
                        ),
                        titleColor: titleColor,
                        subColor: subColor,
                        isDark: isDark,
                      ),
                      _FaqTile(
                        question: tr(
                          vi: 'Xác thực định danh có bắt buộc không?',
                          en: 'Is identity verification required?',
                        ),
                        answer: tr(
                          vi: 'Không bắt buộc cho mọi tính năng. Bạn nên xác thực để tăng hạn mức và bảo mật.',
                          en: 'It is not required for every feature, but it is recommended to increase limits and improve security.',
                        ),
                        titleColor: titleColor,
                        subColor: subColor,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Contact form
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _sent
                      ? Column(
                          children: [
                            const SizedBox(height: 12),
                            Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 56,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              tr(vi: 'Đã gửi yêu cầu!', en: 'Request sent!'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr(
                                vi: 'Bộ phận hỗ trợ sẽ phản hồi sớm.',
                                en: 'Support team will respond soon.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: subColor),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                _sent = false;
                                _subjectController.clear();
                                _messageController.clear();
                              }),
                              child: Text(
                                tr(
                                  vi: 'Gửi yêu cầu mới',
                                  en: 'Send another request',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: iconBg,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.support_agent_rounded,
                                    color: iconColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  tr(
                                    vi: 'Liên hệ hỗ trợ',
                                    en: 'Contact support',
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: titleColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr(
                                vi: 'Gửi yêu cầu hỗ trợ đến quản trị viên.',
                                en: 'Send a support request to the administrator.',
                              ),
                              style: TextStyle(color: subColor, fontSize: 13),
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _subjectController,
                              enabled: !_sending,
                              decoration: InputDecoration(
                                labelText: tr(vi: 'Tiêu đề', en: 'Subject'),
                                prefixIcon: const Icon(Icons.subject_rounded),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _messageController,
                              enabled: !_sending,
                              maxLines: 4,
                              minLines: 3,
                              decoration: InputDecoration(
                                labelText: tr(vi: 'Nội dung', en: 'Message'),
                                alignLabelWithHint: true,
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(bottom: 48),
                                  child: Icon(Icons.message_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _sending ? null : _sendHelpRequest,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
                                label: Text(
                                  tr(vi: 'Gửi yêu cầu', en: 'Send request'),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // Contact info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(vi: 'Thông tin liên hệ', en: 'Contact information'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ContactRow(
                        icon: Icons.email_outlined,
                        label: 'support@kufi.vn',
                        iconColor: iconColor,
                        textColor: subColor,
                      ),
                      const SizedBox(height: 8),
                      _ContactRow(
                        icon: Icons.phone_outlined,
                        label: '1900 xxxx',
                        iconColor: iconColor,
                        textColor: subColor,
                      ),
                      const SizedBox(height: 8),
                      _ContactRow(
                        icon: Icons.access_time_rounded,
                        label: tr(
                          vi: 'Thứ 2 - Thứ 7, 8:00 - 17:00',
                          en: 'Mon - Sat, 8:00 - 17:00',
                        ),
                        iconColor: iconColor,
                        textColor: subColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  final Color titleColor;
  final Color subColor;
  final bool isDark;

  const _FaqTile({
    required this.question,
    required this.answer,
    required this.titleColor,
    required this.subColor,
    required this.isDark,
  });

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: widget.isDark ? const Color(0xFF232A35) : AppColors.vanilla50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: widget.titleColor,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: widget.subColor,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.answer,
                    style: TextStyle(
                      color: widget.subColor,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: textColor, fontSize: 14)),
      ],
    );
  }
}
