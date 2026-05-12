import 'package:flutter/material.dart';

/// Result returned when the host confirms the session configuration.
class CreateRoomResult {
  final String roomId;
  final int sessionMinutes;
  final int splitMinutes;
  final int breakMinutes;

  const CreateRoomResult({
    required this.roomId,
    required this.sessionMinutes,
    required this.splitMinutes,
    required this.breakMinutes,
  });
}

/// Dialog shown to the host before creating a room.
/// Returns a [CreateRoomResult] on confirm, or null if dismissed.
class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({super.key});

  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  final _sessionMinCtrl = TextEditingController(text: '120');
  final _splitMinCtrl   = TextEditingController(text: '25');
  final _breakMinCtrl   = TextEditingController(text: '5');

  @override
  void dispose() {
    _sessionMinCtrl.dispose();
    _splitMinCtrl.dispose();
    _breakMinCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final sessionMin = int.tryParse(_sessionMinCtrl.text) ?? 0;
    final splitMin   = int.tryParse(_splitMinCtrl.text)   ?? 0;
    final breakMin   = int.tryParse(_breakMinCtrl.text)   ?? 0;

    if (sessionMin <= 0 || splitMin <= 0 || breakMin <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All values must be greater than 0.')),
      );
      return;
    }

    if (splitMin > sessionMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus block cannot be longer than total session.')),
      );
      return;
    }

    // Generate a 5-digit room code (10000–99999)
    final roomId = (10000 + DateTime.now().millisecondsSinceEpoch % 90000).toString();

    Navigator.of(context).pop(CreateRoomResult(
      roomId: roomId,
      sessionMinutes: sessionMin,
      splitMinutes: splitMin,
      breakMinutes: breakMin,
    ));
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                border: const OutlineInputBorder(),
                suffixText: 'min',
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField('Total session length', _sessionMinCtrl, '120'),
          _buildField('Focus block length',   _splitMinCtrl,   '25'),
          _buildField('Break length',          _breakMinCtrl,   '5'),
          const SizedBox(height: 8),
          const Text(
            'Number of splits is calculated automatically.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _confirm,
          child: const Text('Create Room'),
        ),
      ],
    );
  }
}
