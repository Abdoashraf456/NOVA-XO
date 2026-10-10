
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bg = Color(0xFF070B18);
const cyan = Color(0xFF00F5FF);
const pink = Color(0xFFFF3CAC);
const purple = Color(0xFF8B5CF6);

void main() => runApp(const NovaXO());

class NovaXO extends StatelessWidget {
  const NovaXO({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NOVA XO',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: cyan,
            brightness: Brightness.dark,
          ),
        ),
        home: const GamePage(),
      );
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with TickerProviderStateMixin {
  final AudioPlayer audio = AudioPlayer();
  final math.Random random = math.Random();

  List<String> board = List.filled(9, '');
  List<int> winningCells = [];

  bool vsComputer = true;
  bool soundOn = true;
  bool gameOver = false;
  bool busy = false;

  String current = 'X';
  String startingPlayer = 'X';
  String difficulty = 'متوسط';
  String status = 'دورك يا بطل!';

  int xScore = 0;
  int oScore = 0;
  int draws = 0;

  late final AnimationController pulse;

  final List<List<int>> wins = const [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    loadScores();
  }

  Future<void> loadScores() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      xScore = p.getInt('nova_x') ?? 0;
      oScore = p.getInt('nova_o') ?? 0;
      draws = p.getInt('nova_draw') ?? 0;
    });
  }

  Future<void> saveScores() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('nova_x', xScore);
    await p.setInt('nova_o', oScore);
    await p.setInt('nova_draw', draws);
  }

  // إنشاء صوت WAV من الكود بدون ملفات صوت خارجية.
  Uint8List makeTone(double frequency, int ms, double volume) {
    const rate = 22050;
    final count = rate * ms ~/ 1000;
    final dataSize = count * 2;
    final bytes = ByteData(44 + dataSize);

    void textAt(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    textAt(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    textAt(8, 'WAVE');
    textAt(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, rate, Endian.little);
    bytes.setUint32(28, rate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    textAt(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < count; i++) {
      final t = i / count;
      final fade = math.min(1.0, t * 30) *
          math.min(1.0, (1 - t) * 10);
      final wave = math.sin(2 * math.pi * frequency * i / rate);
      final sample = (wave * volume * fade * 32767)
          .round()
          .clamp(-32768, 32767)
          .toInt();
      bytes.setInt16(44 + i * 2, sample, Endian.little);
    }

    return bytes.buffer.asUint8List();
  }

  Future<void> tone(double hz, {int ms = 100}) async {
    if (!soundOn) return;
    try {
      await audio.stop();
      await audio.play(BytesSource(makeTone(hz, ms, 0.22)));
    } catch (_) {}
  }

  Future<void> melody(List<double> notes) async {
    if (!soundOn) return;
    for (final n in notes) {
      await tone(n, ms: 145);
      await Future.delayed(const Duration(milliseconds: 55));
    }
  }

  String? winnerOf(List<String> cells) {
    for (final line in wins) {
      if (cells[line[0]].isNotEmpty &&
          cells[line[0]] == cells[line[1]] &&
          cells[line[1]] == cells[line[2]]) {
        return cells[line[0]];
      }
    }
    return null;
  }

  Future<void> tapCell(int i) async {
    if (gameOver || busy || board[i].isNotEmpty) return;
    if (vsComputer && current == 'O') return;

    setState(() => board[i] = current);
    await tone(620, ms: 65);
    await checkResult();

    if (!mounted || gameOver) return;

    setState(() {
      current = current == 'X' ? 'O' : 'X';
      status = vsComputer
          ? (current == 'X' ? 'دورك يا بطل!' : 'الكمبيوتر بيفكر...')
          : 'دور اللاعب ${current == 'X' ? 'الأول' : 'التاني'}';
    });

    if (vsComputer && current == 'O') {
      await computerTurn();
    }
  }

  Future<void> computerTurn() async {
    busy = true;
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted || gameOver) {
      busy = false;
      return;
    }

    final move = chooseMove();
    if (move >= 0) {
      setState(() => board[move] = 'O');
      await tone(420, ms: 80);
      await checkResult();
    }

    if (mounted && !gameOver) {
      setState(() {
        current = 'X';
        status = 'دورك يا بطل!';
      });
    }
    busy = false;
  }

  int chooseMove() {
    final empty = [
      for (int i = 0; i < 9; i++)
        if (board[i].isEmpty) i
    ];
    if (empty.isEmpty) return -1;

    if (difficulty == 'سهل') {
      return empty[random.nextInt(empty.length)];
    }

    // حاول يكسب أو يمنع اللاعب من الفوز.
    for (final i in empty) {
      board[i] = 'O';
      final win = winnerOf(board) == 'O';
      board[i] = '';
      if (win) return i;
    }

    if (difficulty == 'متوسط') {
      for (final i in empty) {
        board[i] = 'X';
        final danger = winnerOf(board) == 'X';
        board[i] = '';
        if (danger) return i;
      }
      if (board[4].isEmpty) return 4;
      final corners = [0, 2, 6, 8]
          .where((i) => board[i].isEmpty)
          .toList();
      if (corners.isNotEmpty) {
        return corners[random.nextInt(corners.length)];
      }
      return empty[random.nextInt(empty.length)];
    }

    // الصعب: خوارزمية تجعل الكمبيوتر صعب الهزيمة.
    int best = -9999;
    int bestMove = empty.first;
    for (final i in empty) {
      board[i] = 'O';
      final score = minimax(false, 0);
      board[i] = '';
      if (score > best) {
        best = score;
        bestMove = i;
      }
    }
    return bestMove;
  }

  int minimax(bool maximizing, int depth) {
    final w = winnerOf(board);
    if (w == 'O') return 10 - depth;
    if (w == 'X') return depth - 10;
    if (!board.contains('')) return 0;

    int best = maximizing ? -9999 : 9999;
    for (int i = 0; i < 9; i++) {
      if (board[i].isEmpty) {
        board[i] = maximizing ? 'O' : 'X';
        final score = minimax(!maximizing, depth + 1);
        board[i] = '';
        best = maximizing
            ? math.max(best, score)
            : math.min(best, score);
      }
    }
    return best;
  }

  Future<void> checkResult() async {
    final w = winnerOf(board);

    if (w != null) {
      final line = wins.firstWhere(
        (l) => l.every((i) => board[i] == w),
      );

      setState(() {
        winningCells = line;
        gameOver = true;
        if (w == 'X') {
          xScore++;
          status = vsComputer
              ? '🔥 كسبت يا أسطورة!'
              : '🏆 اللاعب الأول كسب!';
        } else {
          oScore++;
          status = vsComputer
              ? '🤖 الكمبيوتر كسب الجولة!'
              : '🏆 اللاعب التاني كسب!';
        }
      });
      await saveScores();
      if (w == 'X') {
        await melody([523, 659, 784, 1046]);
      } else {
        await melody([440, 370, 294]);
      }
      return;
    }

    if (!board.contains('')) {
      setState(() {
        gameOver = true;
        draws++;
        status = '🤝 تعادل! جولة قوية';
      });
      await saveScores();
      await melody([500, 500, 500]);
    }
  }

  void nextRound() {
    final w = winnerOf(board);
    setState(() {
      // الفائز يبدأ الجولة التالية، والتعادل يبقي نفس البادئ.
      if (w != null) startingPlayer = w;
      board = List.filled(9, '');
      winningCells = [];
      current = startingPlayer;
      gameOver = false;
      busy = false;
      status = vsComputer
          ? (current == 'X' ? 'دورك يا بطل!' : 'الكمبيوتر بيبدأ...')
          : 'دور اللاعب ${current == 'X' ? 'الأول' : 'التاني'}';
    });
    if (vsComputer && current == 'O') computerTurn();
  }

  void changeMode(bool computer) {
    setState(() {
      vsComputer = computer;
      board = List.filled(9, '');
      winningCells = [];
      current = 'X';
      startingPlayer = 'X';
      gameOver = false;
      busy = false;
      status = computer ? 'دورك يا بطل!' : 'دور اللاعب الأول';
    });
    tone(700);
  }

  void resetAll() {
    setState(() {
      xScore = 0;
      oScore = 0;
      draws = 0;
      board = List.filled(9, '');
      winningCells = [];
      current = 'X';
      startingPlayer = 'X';
      gameOver = false;
      busy = false;
      status = 'دورك يا بطل!';
    });
    saveScores();
    tone(700);
  }

  @override
  void dispose() {
    pulse.dispose();
    audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: GridPainter()),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt, color: cyan, size: 34),
                      const SizedBox(width: 8),
                      const Text(
                        'NOVA',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const Spacer(),
                      iconButton(
                        soundOn ? Icons.volume_up : Icons.volume_off,
                        soundOn ? cyan : Colors.white38,
                        () {
                          setState(() => soundOn = !soundOn);
                          if (soundOn) tone(700);
                        },
                      ),
                      const SizedBox(width: 8),
                      iconButton(Icons.restart_alt, pink, resetAll),
                    ],
                  ),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: pulse,
                    builder: (_, __) => Text(
                      'NOVA XO',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        shadows: [
                          Shadow(
                            color: cyan.withOpacity(0.4 + pulse.value * 0.4),
                            blurRadius: 24,
                          ),
                          Shadow(color: pink.withOpacity(0.35), blurRadius: 35),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'THE NEON BATTLE BEGINS',
                    style: TextStyle(
                      color: cyan,
                      fontSize: 10,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: scoreCard('أنت • X', xScore, cyan)),
                      const SizedBox(width: 8),
                      Expanded(child: scoreCard('تعادل', draws, Colors.white70)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: scoreCard(
                          vsComputer ? 'الكمبيوتر • O' : 'اللاعب الثاني • O',
                          oScore,
                          pink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: modeButton(
                          '🤖 ضد الكمبيوتر',
                          vsComputer,
                          () => changeMode(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: modeButton(
                          '👥 لاعبين',
                          !vsComputer,
                          () => changeMode(false),
                        ),
                      ),
                    ],
                  ),
                  if (vsComputer) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('الصعوبة', style: TextStyle(color: Colors.white60)),
                        const SizedBox(width: 10),
                        for (final level in ['سهل', 'متوسط', 'صعب'])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 5),
                              child: modeButton(
                                level,
                                difficulty == level,
                                () {
                                  setState(() {
                                    difficulty = level;
                                    board = List.filled(9, '');
                                    winningCells = [];
                                    current = 'X';
                                    startingPlayer = 'X';
                                    gameOver = false;
                                    busy = false;
                                    status = 'دورك يا بطل!';
                                  });
                                  tone(650);
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1426),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(color: cyan.withOpacity(0.35)),
                      boxShadow: [
                        BoxShadow(color: cyan.withOpacity(0.09), blurRadius: 28),
                      ],
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 9,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (_, i) {
                          final value = board[i];
                          final color = value == 'X' ? cyan : pink;
                          final isWin = winningCells.contains(i);
                          return InkWell(
                            onTap: () => tapCell(i),
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              decoration: BoxDecoration(
                                color: isWin
                                    ? color.withOpacity(0.22)
                                    : const Color(0xFF141C30),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isWin
                                      ? color
                                      : value.isNotEmpty
                                          ? color.withOpacity(0.6)
                                          : Colors.white10,
                                  width: isWin ? 2 : 1,
                                ),
                                boxShadow: isWin
                                    ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 20)]
                                    : [],
                              ),
                              child: Center(
                                child: AnimatedScale(
                                  scale: value.isEmpty ? 0.5 : 1,
                                  curve: Curves.elasticOut,
                                  duration: const Duration(milliseconds: 350),
                                  child: Text(
                                    value,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 52,
                                      fontWeight: FontWeight.w900,
                                      shadows: [
                                        Shadow(color: color.withOpacity(0.65), blurRadius: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: double.infinity,
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: purple.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: purple.withOpacity(0.4)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          gameOver ? 'انتهت الجولة!' : 'الدور الحالي: $current',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: nextRound,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('جولة جديدة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cyan,
                            foregroundColor: bg,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              board = List.filled(9, '');
                              winningCells = [];
                              current = 'X';
                              startingPlayer = 'X';
                              gameOver = false;
                              busy = false;
                              status = vsComputer ? 'دورك يا بطل!' : 'دور اللاعب الأول';
                            });
                            tone(650);
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: pink,
                            side: const BorderSide(color: pink),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'N O V A   X O   •   ENTER THE ARENA',
                    style: TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget iconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }

  Widget scoreCard(String title, int score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text('$score', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 5),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget modeButton(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? cyan.withOpacity(0.12) : Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: selected ? cyan.withOpacity(0.65) : Colors.white12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? cyan : Colors.white60,
          ),
        ),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cyan.withOpacity(0.035)
      ..strokeWidth = 0.6;
    const gap = 28.0;

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}