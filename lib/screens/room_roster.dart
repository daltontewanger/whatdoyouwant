import 'package:flutter/material.dart';

import '../services/nickname.dart';
import '../services/room_backend.dart';

/// Whether the signed-in person can have a nickname: verified accounts only,
/// the same people who can start a search.
bool canHaveNickname(BuildContext context) {
  final user = RoomBackendScope.maybeOf(context)?.accounts?.auth.currentUser;
  return user != null && !user.isAnonymous && user.emailVerified;
}

/// "Who's here": everyone in the room as a chip with their first letter,
/// guests folded into one chip. Names only; votes stay anonymous.
class RoomRoster extends StatelessWidget {
  const RoomRoster({
    super.key,
    required this.people,
    required this.memberCount,
    this.capacity,
  });

  final List<RoomPerson> people;
  final int memberCount;

  /// Shown as "6 of 15" to the host, who decides when to start.
  final int? capacity;

  // Each keeps white text at AA contrast.
  static const colors = [
    Color(0xFF2F7A5C),
    Color(0xFFB8432F),
    Color(0xFF3B6EA5),
    Color(0xFF8A5A00),
    Color(0xFF7A4F9E),
    Color(0xFF1F6F78),
  ];
  static const guestColor = Color(0xFF6B7671);

  /// The same nickname gets the same color in every room.
  static Color colorFor(String name) {
    var hash = 0;
    for (final unit in name.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = people.isEmpty ? memberCount : people.length;
    final named = [
      for (final p in people)
        if (!p.guest || p.host || p.you) p,
    ];
    final guests = people.length - named.length;
    final chips = [
      for (final person in named) _chip(theme, person),
      if (guests > 0)
        _chip(theme, null, label: guests == 1 ? '1 guest' : '$guests guests'),
    ];
    final spoken = [
      for (final person in named) _spoken(person),
      if (guests > 0) guests == 1 ? '1 guest' : '$guests guests',
    ].join('; ');
    return Semantics(
      container: true,
      label:
          "Who's here, $count ${count == 1 ? 'person' : 'people'}"
          '${spoken.isEmpty ? '' : ': $spoken'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Who's here",
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                capacity == null ? '$count' : '$count of $capacity',
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (chips.isEmpty)
            Text(
              count == 1 ? 'Only you so far' : '$count people',
              style: theme.textTheme.bodyMedium,
            )
          else
            Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
      ),
    );
  }

  static String _spoken(RoomPerson person) => [
    person.name ?? (person.host ? 'Host' : 'Guest'),
    if (person.host && person.name != null) 'host',
    if (person.you) 'you',
  ].join(', ');

  Widget _chip(ThemeData theme, RoomPerson? person, {String? label}) {
    final name = person?.name;
    final text = label ?? name ?? (person!.host ? 'Host' : 'Guest');
    final tags = [
      if (person != null && person.host && name != null) 'host',
      if (person?.you == true) 'you',
    ].join(' · ');
    final guest = name == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
      decoration: BoxDecoration(
        color: guest ? const Color(0xFFF4F4F4) : const Color(0xFFF1F6F3),
        border: Border.all(
          color: guest ? const Color(0xFFE2E2E2) : const Color(0xFFDCE8E1),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: guest ? guestColor : colorFor(name),
            child: Text(
              guest ? 'G' : name.characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              tags,
              style: theme.textTheme.bodySmall!.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tells an account holder without a nickname that the room sees them as a
/// guest, with a way to pick one.
class NicknameNudge extends StatelessWidget {
  const NicknameNudge({super.key});

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5A4300);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: const Color(0xFFFFF1C9),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFF7C948), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showNicknameDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'You show as "Guest" to everyone else. ',
                  ),
                  TextSpan(
                    text: 'Add a nickname',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                    semanticsLabel: 'Add a nickname',
                  ),
                ],
              ),
              style: theme.textTheme.bodyMedium!.copyWith(color: brown),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a nickname and saves it. Returns the saved nickname ('' when
/// cleared), or null when the person cancelled.
Future<String?> showNicknameDialog(
  BuildContext context, {
  String current = '',
}) {
  final backend = RoomBackendScope.of(context).backend;
  return showDialog<String>(
    context: context,
    builder: (_) => _NicknameDialog(backend: backend, current: current),
  );
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.backend, required this.current});
  final RoomBackend backend;
  final String current;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _field = TextEditingController(text: widget.current);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = Nickname.problem(_field.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.backend.setNickname(
        Nickname.tidy(_field.text),
      );
      if (mounted) Navigator.of(context).pop(saved ?? '');
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = nicknameErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your nickname'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _field,
          autofocus: true,
          enabled: !_saving,
          maxLength: Nickname.maxLength,
          textCapitalization: TextCapitalization.words,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: 'Nickname',
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Shown to people in rooms you join, so they know it's you. It "
          "doesn't have to be unique. Leave it empty to show as \"Guest\".",
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
    ],
  );
}

/// The Account row for the nickname, for verified accounts.
class NicknameTile extends StatefulWidget {
  const NicknameTile({super.key});

  @override
  State<NicknameTile> createState() => _NicknameTileState();
}

class _NicknameTileState extends State<NicknameTile> {
  String? _nickname;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    RoomBackendScope.of(context).backend
        .nickname()
        .then((name) {
          if (mounted) setState(() => _nickname = name);
        })
        .catchError((Object _) {});
  }

  Future<void> _edit() async {
    final saved = await showNicknameDialog(context, current: _nickname ?? '');
    if (saved != null && mounted) {
      setState(() => _nickname = saved.isEmpty ? null : saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _nickname;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor:
              name == null ? RoomRoster.guestColor : RoomRoster.colorFor(name),
          child: Text(
            name == null ? 'G' : name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: const Text('Nickname'),
        subtitle: Text(
          name == null
              ? 'Not set · You show as "Guest" in rooms'
              : '$name · Shown to people in your rooms',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _edit,
      ),
    );
  }
}
