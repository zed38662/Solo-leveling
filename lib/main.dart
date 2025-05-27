import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solo Leveling Life App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ClassSelectionScreen(),
    );
  }
}

// Class Selection Screen
class ClassSelectionScreen extends StatefulWidget {
  @override
  _ClassSelectionScreenState createState() => _ClassSelectionScreenState();
}

class _ClassSelectionScreenState extends State<ClassSelectionScreen> {
  final List<String> classes = ['Warrior', 'Mage', 'Rogue', 'Archer', 'Healer'];
  String? selectedClass;

  @override
  void initState() {
    super.initState();
    _loadSelectedClass();
  }

  Future<void> _loadSelectedClass() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedClass = prefs.getString('playerClass') ?? classes[0];
    });
  }

  Future<void> _saveSelectedClass(String chosen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerClass', chosen);
  }

  void _onClassSelected(String chosen) {
    setState(() => selectedClass = chosen);
  }

  void _proceed() async {
    if (selectedClass != null) {
      await _saveSelectedClass(selectedClass!);
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => HomeScreen(playerClass: selectedClass!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Select Your Class')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...classes.map((c) => RadioListTile<String>(
                title: Text(c),
                value: c,
                groupValue: selectedClass,
                onChanged: _onClassSelected,
              )),
          ElevatedButton(
            onPressed: selectedClass == null ? null : _proceed,
            child: Text('Start Journey'),
          )
        ],
      ),
    );
  }
}

// Home Screen with Stats & Quests
class HomeScreen extends StatefulWidget {
  final String playerClass;
  HomeScreen({required this.playerClass});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late OpenAIService openAIService;
  late PlayerStats playerStats;
  List<Quest> quests = [];
  bool loading = false;
  final AudioPlayer audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    openAIService = OpenAIService(dotenv.env['OPENAI_API_KEY'] ?? '');
    playerStats = PlayerStats();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      playerStats = PlayerStats.fromPrefs(prefs);
      quests = Quest.listFromJson(prefs.getString('questsJson') ?? '[]');
    });

    // If no quests saved, generate new ones
    if (quests.isEmpty) _generateQuests();
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('level', playerStats.level);
    await prefs.setInt('exp', playerStats.exp);
    await prefs.setInt('intelligence', playerStats.intelligence);
    await prefs.setInt('physique', playerStats.physique);
    await prefs.setInt('logic', playerStats.logic);
    await prefs.setInt('skills', playerStats.skills);
    await prefs.setInt('attractiveness', playerStats.attractiveness);
    await prefs.setInt('learning', playerStats.learning);
    await prefs.setString('questsJson', jsonEncode(quests.map((q) => q.toJson()).toList()));
  }

  Future<void> _generateQuests() async {
    setState(() => loading = true);
    try {
      final newQuests = await openAIService.generateQuests(widget.playerClass, playerStats.toMap());
      setState(() {
        quests = newQuests;
        loading = false;
      });
      await _saveProgress();
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load quests: $e')));
    }
  }

  Future<void> _completeQuest(int index) async {
    final quest = quests[index];
    playerStats.gainExperience(quest.expReward);
    quest.statRewards.forEach((stat, value) {
      playerStats.increaseStat(stat, value);
    });
    setState(() {
      quests.removeAt(index);
    });
    await _saveProgress();

    // Play success sound
    await audioPlayer.play(AssetSource('sounds/success.mp3'));

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Quest completed! Stats updated.')));
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Solo Leveling Life - ${widget.playerClass}'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: 'Generate New Quests',
            onPressed: _generateQuests,
          ),
        ],
      ),
      body: Column(
        children: [
          StatsWidget(playerStats: playerStats),
          Expanded(
            child: loading
                ? Center(child: CircularProgressIndicator())
                : quests.isEmpty
                    ? Center(child: Text('No quests. Tap refresh to generate new quests.'))
                    : ListView.builder(
                        itemCount: quests.length,
                        itemBuilder: (context, index) {
                          final quest = quests[index];
                          return Card(
                            margin: EdgeInsets.all(8),
                            child: ListTile(
                              title: Text(quest.title),
                              subtitle: Text(quest.description),
                              trailing: ElevatedButton(
                                child: Text('Complete'),
                                onPressed: () => _completeQuest(index),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class StatsWidget extends StatelessWidget {
  final PlayerStats playerStats;
  const StatsWidget({required this.playerStats});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Text('Level: ${playerStats.level}   EXP: ${playerStats.exp} / ${playerStats.expToNextLevel()}',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 16,
              children: [
                StatChip(label: 'Intelligence', value: playerStats.intelligence),
                StatChip(label: 'Physique', value: playerStats.physique),
                StatChip(label: 'Logic', value: playerStats.logic),
                StatChip(label: 'Skills', value: playerStats.skills),
                StatChip(label: 'Attractiveness', value: playerStats.attractiveness),
                StatChip(label: 'Learning', value: playerStats.learning),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  final String label;
  final int value;
  const StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Colors.blue.shade100,
    );
  }
}

// Data and service classes

class PlayerStats {
  int intelligence;
  int physique;
  int logic;
  int skills;
  int attractiveness;
  int learning;
  int level;
  int exp;

  PlayerStats({
    this.intelligence = 5,
    this.physique = 5,
    this.logic = 5,
    this.skills = 5,
    this.attractiveness = 5,
    this.learning = 5,
    this.level = 1,
    this.exp = 0,
  });

  void gainExperience(int amount) {
    exp += amount;
    while (exp >= expToNextLevel()) {
      exp -= expToNextLevel();
      level++;
    }
  }

  int expToNextLevel() => 100 + (level - 1) * 50;

  void increaseStat(String stat, int value) {
    switch (stat.toLowerCase()) {
      case 'intelligence':
        intelligence += value;
        break;
      case 'physique':
        physique += value;
        break;
      case 'logic':
        logic += value;
        break;
      case 'skills':
        skills += value;
        break;
      case 'attractiveness':
        attractiveness += value;
        break;
      case 'learning':
        learning += value;
        break;
    }
  }

  Map<String, int> toMap() {
    return {
      'intelligence': intelligence,
      'physique': physique,
      'logic': logic,
      'skills': skills,
      'attractiveness': attractiveness,
      'learning': learning,
    };
  }

  // Load from SharedPreferences
  factory PlayerStats.fromPrefs(SharedPreferences prefs) {
    return PlayerStats(
      intelligence: prefs.getInt('intelligence') ?? 5,
      physique: prefs.getInt('physique') ?? 5,
      logic: prefs.getInt('logic') ?? 5,
      skills: prefs.getInt('skills') ?? 5,
      attractiveness: prefs.getInt('attractiveness') ?? 5,
      learning: prefs.getInt('learning') ?? 5,
      level: prefs.getInt('level') ?? 1,
      exp: prefs.getInt('exp') ?? 0,
    );
  }
}

class Quest {
  final String title;
  final String description;
  final int expReward;
  final Map<String, int> statRewards;

  Quest({
    required this.title,
    required this.description,
    required this.expReward,
    required this.statRewards,
  });

  factory Quest.fromJson(Map<String, dynamic> json) {
    final statRewardsMap = <String, int>{};
    if (json['statRewards'] != null) {
      json['statRewards'].forEach((key, value) {
        statRewardsMap[key.toString()] = (value as num).toInt();
      });
    }
    return Quest(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      expReward: (json['expReward'] ?? 0) as int,
      statRewards: statRewardsMap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'expReward': expReward,
