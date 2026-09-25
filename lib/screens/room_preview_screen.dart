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

class _RoomPreviewScreenState extends State<RoomPreviewScreen> {
  final code = TextEditingController();
  final requestId = const Uuid().v4();
  final uid = FirebaseAuth.instance.currentUser?.uid;
  String? roomCode;
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
      if (mounted) {
        setState(
          () =>
              message =
                  error.code == 'resource-exhausted'
                      ? 'Too many attempts. Wait and try again.'
                      : 'Action unavailable. Check your account, room code and room status.',
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

  Future<void> enter(String function, Map<String, String> data) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable(function)
        .call(data);
    if (mounted) setState(() => roomCode = response.data['roomCode'] as String);
  }

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
            if (roomCode == null) ...[
              ElevatedButton(
                onPressed:
                    busy || !verified
                        ? null
                        : () => perform(
                          () => enter('phase1CreateRoom', {
                            'requestId': requestId,
                          }),
                        ),
                child: const Text('Create test room'),
              ),
              if (!verified)
                const Text('A verified account is required to create a room.'),
              TextField(
                controller: code,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Room code'),
              ),
              ElevatedButton(
                onPressed:
                    busy
                        ? null
                        : () => perform(
                          () => enter('phase1JoinRoom', {
                            'roomCode': code.text.trim().toUpperCase(),
                          }),
                        ),
                child: const Text('Join or reconnect'),
              ),
            ] else ...[
              SelectableText('Room code: $roomCode'),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream:
                    FirebaseFirestore.instance
                        .doc('rooms/$roomCode')
                        .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Room access is unavailable.');
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final room = snapshot.data!.data();
                  if (room == null) return const Text('Room unavailable.');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${room['status']} · Members: ${room['memberCount']}',
                      ),
                      if (room['creator'] == uid && room['status'] == 'lobby')
                        ElevatedButton(
                          onPressed:
                              busy
                                  ? null
                                  : () => perform(() async {
                                    await FirebaseFunctions.instance
                                        .httpsCallable('phase1Search')
                                        .call({'roomCode': roomCode});
                                  }),
                          child: const Text('Start fictional restaurant deck'),
                        ),
                      if (room['status'] == 'voting') _ballots(),
                    ],
                  );
                },
              ),
            ],
            if (busy) const LinearProgressIndicator(),
            if (message.isNotEmpty) Text(message),
          ],
        );
      },
    ),
  );

  Widget _ballots() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream:
        FirebaseFirestore.instance
            .collection('rooms/$roomCode/candidates')
            .snapshots(),
    builder: (context, candidates) {
      if (candidates.hasError) return const Text('Deck access unavailable.');
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('rooms/$roomCode/votes/$uid/ballot')
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
                                            await FirebaseFirestore.instance
                                                .doc(
                                                  'rooms/$roomCode/votes/$uid/ballot/${candidate.id}',
                                                )
                                                .set({
                                                  'liked': liked,
                                                  'at':
                                                      FieldValue.serverTimestamp(),
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
