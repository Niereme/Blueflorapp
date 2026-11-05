import 'package:flutter/material.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';

/// Conserva el selector Material habitual; usa entrada vertical desplazable
/// cuando el texto grande no cabe en su disposición de tamaño fijo.
Future<TimeOfDay?> showFloraTimePicker(
  BuildContext context,
  TimeOfDay initial,
) {
  if (MediaQuery.textScalerOf(context).scale(16) <= 24) {
    return showTimePicker(context: context, initialTime: initial);
  }
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _AccessibleTimeDialog(initial: initial),
  );
}

class _AccessibleTimeDialog extends StatefulWidget {
  const _AccessibleTimeDialog({required this.initial});
  final TimeOfDay initial;
  @override
  State<_AccessibleTimeDialog> createState() => _AccessibleTimeDialogState();
}

class _AccessibleTimeDialogState extends State<_AccessibleTimeDialog> {
  final form = GlobalKey<FormState>();
  late final hour = TextEditingController(
    text: widget.initial.hour.toString().padLeft(2, '0'),
  );
  late final minute = TextEditingController(
    text: widget.initial.minute.toString().padLeft(2, '0'),
  );
  @override
  void dispose() {
    hour.dispose();
    minute.dispose();
    super.dispose();
  }

  void submit() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(
      context,
      TimeOfDay(
        hour: int.parse(hour.text.trim()),
        minute: int.parse(minute.text.trim()),
      ),
    );
  }

  String? validate(String? value, int max) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null || number < 0 || number > max
        ? 'Escribe un número entero entre 0 y $max.'
        : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Hora preferida'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Formato de 24 horas.'),
          const SizedBox(height: FloraTokens.padding),
          TextFormField(
            controller: hour,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Hora',
              helperText: 'De 0 a 23',
              errorMaxLines: 4,
            ),
            validator: (value) => validate(value, 23),
          ),
          const SizedBox(height: FloraTokens.padding),
          TextFormField(
            controller: minute,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => submit(),
            decoration: const InputDecoration(
              labelText: 'Minutos',
              helperText: 'De 0 a 59',
              errorMaxLines: 4,
            ),
            validator: (value) => validate(value, 59),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      FilledButton(
        onPressed: submit,
        child: Text(MaterialLocalizations.of(context).okButtonLabel),
      ),
    ],
  );
}
