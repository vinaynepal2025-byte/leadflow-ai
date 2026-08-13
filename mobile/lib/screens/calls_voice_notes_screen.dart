import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:io';
import '../services/api_service.dart';
import 'call_log_tab.dart';

class CallsVoiceNotesScreen extends StatelessWidget {
  final String leadId;
  final String? leadPhone;
  final String? leadName;
  const CallsVoiceNotesScreen({super.key, required this.leadId, this.leadPhone, this.leadName});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calls & Voice Notes'),
          bottom: const TabBar(tabs: [Tab(text: 'Call Log'), Tab(text: 'Voice Notes')]),
        ),
        body: TabBarView(children: [
          CallLogTab(leadId: leadId, leadPhone: leadPhone, leadName: leadName),
          _VoiceNotesTab(leadId: leadId),
        ]),
      ),
    );
  }
}

class _VoiceNotesTab extends StatefulWidget {
  final String leadId;
  const _VoiceNotesTab({required this.leadId});

  @override
  State<_VoiceNotesTab> createState() => _VoiceNotesTabState();
}

class _VoiceNotesTabState extends State<_VoiceNotesTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getVoiceNotes(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getVoiceNotes(widget.leadId));

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.single.path == null) return;
    await _api.uploadVoiceNote(leadId: widget.leadId, filePath: result.files.single.path!, fileName: result.files.single.name, recordedBy: 'Counselor');
    _refresh();
  }

  // Downloads the voice note's real audio bytes from the server, saves
  // them to a temp file, then hands off to Android's native share sheet
  // — this genuinely attaches the audio to WhatsApp (or any app the
  // counselor picks), not just a text link. Same pattern already proven
  // for Flyer Studio's "Share to WhatsApp".
  Future<void> _shareToWhatsApp(Map<String, dynamic> note) async {
    try {
      final bytes = await _api.downloadVoiceNoteBytes(note['id']);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${note['file_name']}');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    }
  }

  Future<void> _showAddOptions() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.mic),
              title: const Text('Record a voice note'),
              onTap: () {
                Navigator.pop(context);
                _showRecordSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload an audio file'),
              onTap: () {
                Navigator.pop(context);
                _upload();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Real microphone recording, with playback preview BEFORE it's attached
  // — the counselor can listen back and re-record if it's not right,
  // rather than the note being finalized the moment recording stops.
  Future<void> _showRecordSheet() async {
    final recorder = AudioRecorder();
    final player = AudioPlayer();
    bool recording = false;
    bool hasRecording = false;
    bool playing = false;
    bool uploading = false;
    int elapsedSeconds = 0;
    String? recordedPath;
    Timer? ticker;

    Future<void> startRecording(void Function(void Function()) setSheetState) async {
      if (!await recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is needed to record a voice note')),
          );
        }
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/voicenote_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(), path: path);
      recordedPath = path;
      elapsedSeconds = 0;
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedSeconds++;
        setSheetState(() {});
      });
      setSheetState(() {
        recording = true;
        hasRecording = false;
      });
    }

    Future<void> stopRecording(void Function(void Function()) setSheetState) async {
      await recorder.stop();
      ticker?.cancel();
      setSheetState(() {
        recording = false;
        hasRecording = true;
      });
    }

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                recording ? 'Recording... ${elapsedSeconds}s' : (hasRecording ? 'Preview before saving' : 'Voice Note'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (!recording && !hasRecording)
                IconButton.filled(
                  iconSize: 48,
                  icon: const Icon(Icons.mic),
                  onPressed: () => startRecording(setSheetState),
                ),
              if (recording)
                IconButton.filled(
                  iconSize: 48,
                  icon: const Icon(Icons.stop),
                  style: IconButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => stopRecording(setSheetState),
                ),
              if (hasRecording && recordedPath != null) ...[
                IconButton.filled(
                  iconSize: 40,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () async {
                    if (playing) {
                      await player.pause();
                      setSheetState(() => playing = false);
                    } else {
                      await player.play(DeviceFileSource(recordedPath!));
                      setSheetState(() => playing = true);
                      player.onPlayerComplete.listen((_) {
                        if (context.mounted) setSheetState(() => playing = false);
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-record'),
                      onPressed: () {
                        setSheetState(() {
                          hasRecording = false;
                          recordedPath = null;
                        });
                      },
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: Text(uploading ? 'Saving...' : 'Use this recording'),
                      onPressed: uploading
                          ? null
                          : () async {
                              setSheetState(() => uploading = true);
                              try {
                                await _api.uploadVoiceNote(
                                  leadId: widget.leadId,
                                  filePath: recordedPath!,
                                  fileName: 'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a',
                                  recordedBy: 'Counselor',
                                );
                                if (context.mounted) Navigator.pop(context);
                                _refresh();
                              } catch (e) {
                                setSheetState(() => uploading = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
                                }
                              }
                            },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  ticker?.cancel();
                  recorder.dispose();
                  player.dispose();
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNote(Map<String, dynamic> note) async {
    final transcriptCtrl = TextEditingController(text: note['transcript'] ?? '');
    String? summary = note['ai_summary'];
    String? error;
    bool summarizing = false;

    final speech = stt.SpeechToText();
    final speechAvailable = await speech.initialize();
    bool listening = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(note['file_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: transcriptCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Transcript (type, paste, or dictate)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: Icon(listening ? Icons.stop : Icons.mic, color: listening ? Colors.red : null),
                      tooltip: speechAvailable
                          ? (listening ? 'Stop dictating' : 'Dictate transcript')
                          : 'Speech recognition not available on this device',
                      onPressed: !speechAvailable
                          ? null
                          : () async {
                              if (listening) {
                                await speech.stop();
                                setSheetState(() => listening = false);
                              } else {
                                setSheetState(() => listening = true);
                                await speech.listen(
                                  onResult: (result) {
                                    setSheetState(() => transcriptCtrl.text = result.recognizedWords);
                                  },
                                );
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    await _api.attachTranscript(note['id'], transcriptCtrl.text.trim());
                    _refresh();
                  },
                  child: const Text('Save Transcript'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(summarizing ? 'Summarizing...' : 'AI Summarize'),
                  onPressed: summarizing
                      ? null
                      : () async {
                          setSheetState(() {
                            summarizing = true;
                            error = null;
                          });
                          try {
                            final s = await _api.summarizeVoiceNote(note['id']);
                            setSheetState(() => summary = s);
                          } catch (e) {
                            setSheetState(() => error = e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            setSheetState(() => summarizing = false);
                          }
                        },
                ),
                if (error != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                ),
                if (summary != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(summary!),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data ?? [];
          if (notes.isEmpty) return const Center(child: Text('No voice notes yet', style: TextStyle(color: Colors.grey)));
          return ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = notes[i];
              return ListTile(
                leading: const Icon(Icons.mic_outlined),
                title: Text(n['file_name']),
                subtitle: Text(n['ai_summary'] != null ? 'Summarized' : (n['transcript'] != null ? 'Transcript added' : 'No transcript yet')),
                trailing: IconButton(
                  icon: const Icon(Icons.share, size: 20),
                  tooltip: 'Share to WhatsApp',
                  onPressed: () => _shareToWhatsApp(n),
                ),
                onTap: () => _openNote(n),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddOptions, child: const Icon(Icons.add)),
    );
  }
}
