import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

// Opt-in emulator preview only; intentionally separate from legacy room flows.
class RoomPreviewScreen extends StatefulWidget {
  const RoomPreviewScreen({super.key});
  @override
  State<RoomPreviewScreen> createState() => _RoomPreviewScreenState();
}

/// Turns what someone typed into a join request: a six-character join code for
/// new members, or the longer room ID that existing members reconnect with.
Map<String, String>? joinRequestFor(String typed) {
  final cleaned = typed.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^[A-HJKMNP-Z2-9]{6}$').hasMatch(cleaned)) {
    return {'joinCode': cleaned};
  }
  if (RegExp(r'^[A-F0-9]{24}$').hasMatch(cleaned)) return {'roomId': cleaned};
  return null;
}

class _RoomPreviewScreenState extends State<RoomPreviewScreen> {
  final code = TextEditingController();
  final requestId = const Uuid().v4();
  final uid = FirebaseAuth.instance.currentUser?.uid;
  String? roomId;
  bool busy = false;
  String message = '';

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('Identity changed');
      }
      await action();
    } on FirebaseException catch (error) {
      // Emulator-only screen; the raw message makes client-side failures diagnosable.
      debugPrint('Room preview action failed: ${error.code} ${error.message}');
      if (mounted) {
        setState(
          () =>
              message =
                  error.code == 'resource-exhausted'
                      ? 'Too many attempts. Wait and try again.'
                      : 'Action unavailable (${error.code}). Check your account, room code and room status.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Return to Accounts and check your session.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, dynamic>> call(
    String function,
    Map<String, String> data,
  ) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable(function)
        .call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> enter(String function, Map<String, String> data) async {
    final result = await call(function, data);
    if (mounted) setState(() => roomId = result['roomId'] as String);
  }

  Widget action(String label, String function) => ElevatedButton(
    onPressed:
        busy ? null : () => perform(() => call(function, {'roomId': roomId!})),
    child: Text(label),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local room preview')),
    body: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) {
        if (uid == null || auth.data?.uid != uid) {
          return const Center(
            child: Text('Session changed. Return to Accounts.'),
          );
        }
        final verified =
            auth.data?.isAnonymous == false && auth.data?.emailVerified == true;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Fictional restaurants only. Invite guests before starting the deck.',
            ),
            if (roomId == null) ...[
              ElevatedButton(
                onPressed:
                    busy || !verified
                        ? null
                        : () => perform(
                          () => enter('createRoom', {'requestId': requestId}),
                        ),
                child: const Text('Create test room'),
              ),
              if (!verified)
                const Text('A verified account is required to create a room.'),
              TextField(
                controller: code,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Join code (or room ID to reconnect)',
                ),
              ),
              ElevatedButton(
                onPressed:
                    busy
                        ? null
                        : () {
                          final request = joinRequestFor(code.text);
                          if (request == null) {
                            setState(
                              () =>
                                  message =
                                      'Enter the 6-character join code or the room ID.',
                            );
                            return;
                          }
                          perform(() => enter('joinRoom', request));
                        },
                child: const Text('Join or reconnect'),
              ),
            ] else
              _room(),
            if (busy) const LinearProgressIndicator(),
            if (message.isNotEmpty) Text(message),
          ],
        );
      },
    ),
  );

  Widget _room() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.doc('rooms/$roomId').snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Room access is unavailable.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final room = snapshot.data!.data();
      if (room == null) return const Text('Room unavailable.');
      final host = room['creator'] == uid;
      final status = room['status'] as String?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (room['joinCode'] != null)
            SelectableText('Join code: ${room['joinCode']}'),
          SelectableText('Room ID (for reconnecting): $roomId'),
          Text('Status: $status · Members: ${room['memberCount']}'),
          if (host && status == 'lobby') ...[
            action('Start fictional restaurant deck', 'startRoom'),
            action('New join code', 'rotateJoinCode'),
            action('Close room', 'closeRoom'),
          ],
          if (status == 'voting') ...[
            _ballots(room['expiresAt'] as Timestamp),
            action('Check results', 'roomResults'),
            if (host) action('Close voting now', 'closeRoom'),
          ],
          if (status == 'closed') _results(room['results']),
        ],
      );
    },
  );

  Widget _results(Object? results) {
    if (results is! Map) return const Text('Room closed before voting.');
    final likes = Map<String, dynamic>.from(results['likes'] as Map);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('rooms/$roomId/candidates')
              .snapshots(),
      builder: (context, candidates) {
        final deck = [...?candidates.data?.docs]..sort(
          (a, b) =>
              (a.data()['order'] as int).compareTo(b.data()['order'] as int),
        );
        final titles = {
          for (final doc in deck) doc.id: doc.data()['title'] as String,
        };
        String name(Object? id) => titles[id] ?? '$id';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Winner: ${name(results['winner'])}'),
            if (results['backup'] != null)
              Text('Backup: ${name(results['backup'])}'),
            Text('Voters: ${results['voters']}'),
            for (final id in deck.isEmpty ? likes.keys : deck.map((d) => d.id))
              Text('${name(id)}: ${likes[id] ?? 0} likes'),
          ],
        );
      },
    );
  }

  Widget _ballots(
    Timestamp expiresAt,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream:
        FirebaseFirestore.instance
            .collection('rooms/$roomId/candidates')
            .orderBy('order')
            .snapshots(),
    builder: (context, candidates) {
      if (candidates.hasError) return const Text('Deck access unavailable.');
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('rooms/$roomId/votes/$uid/ballot')
                .snapshots(),
        builder: (context, votes) {
          if (votes.hasError) return const Text('Ballot access unavailable.');
          final recorded =
              votes.data?.docs.map((doc) => doc.id).toSet() ?? <String>{};
          return Column(
            children: [
              for (final candidate
                  in candidates.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                ListTile(
                  title: Text(candidate.data()['title'] as String),
                  subtitle:
                      recorded.contains(candidate.id)
                          ? const Text('Vote saved')
                          : null,
                  trailing:
                      recorded.contains(candidate.id)
                          ? null
                          : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final liked in [true, false])
                                TextButton(
                                  onPressed:
                                      busy || !votes.hasData
                                          ? null
                                          : () => perform(() async {
                                            // Ballots carry the room's expiry so
                                            // they are cleaned up with it.
                                            await FirebaseFirestore.instance
                                                .doc(
                                                  'rooms/$roomId/votes/$uid/ballot/${candidate.id}',
                                                )
                                                .set({
                                                  'liked': liked,
                                                  'at':
                                                      FieldValue.serverTimestamp(),
                                                  'expiresAt': expiresAt,
                                                });
                                          }),
                                  child: Text(liked ? 'Like' : 'Pass'),
                                ),
                            ],
                          ),
                ),
            ],
          );
        },
      );
    },
  );
}
