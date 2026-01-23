import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database_helper.dart';
import 'licenses_screen.dart';
import 'package:pdf/widgets.dart' as pw;

class DateScreen extends StatefulWidget {
  const DateScreen({super.key});

  @override
  State<DateScreen> createState() => _DateScreenState();
}

class _DateScreenState extends State<DateScreen> {
  DateTime? _initialDate;
  DateTime? _finalDate;
  TimeOfDay? _initialTime;
  TimeOfDay? _finalTime;

  // ✅ Nome do evento
  final TextEditingController _eventoController = TextEditingController();

  String _encryptedData = '';
  String _decodedInfo = '';
  String _error = '';

  // ======= CONFIG (mantenha esse segredo só no app / ofuscado no build) =======
  static const String _secret = 'mysecretkey12345'; // pode trocar
  static const int _version = 1;

  // Base (UTC) para reduzir o tamanho do timestamp
  static final DateTime _baseUtc = DateTime.utc(2024, 1, 1, 0, 0);

  // ✅ BASE36 (0-9 + A-Z) => sem minúsculas
  static const String _b36 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  // ✅ Token final: 16 chars datas criptografadas + 4 chars TAG do evento
  static const int _tokenLen = 20;
  static const int _datePartLen = 16;
  static const int _eventTagLen = 4;

  // ✅ Validação: só pode gerar/exportar se tiver evento
  bool get _eventoPreenchido => _eventoController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initialDate = DateTime.now();
    _finalDate = DateTime.now();
    _initialTime = const TimeOfDay(hour: 0, minute: 0);
    _finalTime = const TimeOfDay(hour: 23, minute: 59);

    _encryptedData = '';
    _decodedInfo = '';
    _error = '';
  }

  @override
  void dispose() {
    _eventoController.dispose();
    super.dispose();
  }

  // ======================= UI HELPERS =======================
  DateTime _combineLocal(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _fmtDateTimeLocal(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd-$mm-$yyyy $hh:$mi';
  }

  void _showSnack(
    String msg, {
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), duration: duration));
  }

  String _sanitizeFileName(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'EVENTO';
    return t.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  // ======================= EVENT TAG (4 chars) =======================
  int _eventTagValue(String eventName) {
    final normalized = eventName.trim().toUpperCase();
    if (normalized.isEmpty) return 0;

    final bytes = _utf8(normalized);
    final h = crypto.sha256.convert(bytes).bytes;

    final v32 =
        ((h[0] & 0xFF) << 24) |
        ((h[1] & 0xFF) << 16) |
        ((h[2] & 0xFF) << 8) |
        (h[3] & 0xFF);

    return v32 % 1679616; // 36^4
  }

  String _eventTagChars(String eventName) {
    final tag = _eventTagValue(eventName);
    return _toBase36Fixed(BigInt.from(tag), _eventTagLen);
  }

  // ======================= TOKEN CORE =======================
  Future<void> _updateEncryptedData() async {
    _error = '';
    _decodedInfo = '';

    if (!_eventoPreenchido) {
      _encryptedData = '';
      _error = 'Preencha o Nome do Evento para gerar a licença.';
      return;
    }

    if (_initialDate == null ||
        _finalDate == null ||
        _initialTime == null ||
        _finalTime == null) {
      _encryptedData = '';
      _error = 'Selecione as datas e horários.';
      return;
    }

    final startLocal = _combineLocal(_initialDate!, _initialTime!);
    final endLocal = _combineLocal(_finalDate!, _finalTime!);

    if (!endLocal.isAfter(startLocal) && endLocal != startLocal) {
      _error = 'Data/hora final precisa ser maior ou igual à inicial.';
      _encryptedData = '';
      return;
    }

    try {
      final token = _encodeToken(startLocal, endLocal, _eventoController.text);
      _encryptedData = token;

      final decoded = _decodeToken(token);
      _decodedInfo =
          'Início: ${_fmtDateTimeLocal(decoded.$1)} / Fim: ${_fmtDateTimeLocal(decoded.$2)}';
    } catch (e) {
      _encryptedData = '';
      _decodedInfo = '';
      _error = 'Erro ao gerar/ler token: $e';
    }
  }

  /// ✅ Token FIXO de 20 caracteres, SOMENTE 0-9 e A-Z
  /// Formato: [16 chars datas criptografadas][4 chars TAG do evento]
  String _encodeToken(
    DateTime startLocal,
    DateTime endLocal,
    String eventName,
  ) {
    final startUtc = startLocal.toUtc();
    final endUtc = endLocal.toUtc();

    final startMinutes = startUtc.difference(_baseUtc).inMinutes;
    final durationMinutes = endUtc.difference(startUtc).inMinutes;

    if (startMinutes < 0) {
      throw Exception('Data inicial menor que a base (01/01/2024).');
    }
    if (startMinutes > 0xFFFFFFFF) {
      throw Exception('startMinutes excedeu 32 bits.');
    }
    if (durationMinutes < 0 || durationMinutes > 0xFFFFF) {
      throw Exception('durationMinutes excedeu 20 bits (máx ~728 dias).');
    }

    final v = (_version & 0xF);
    final sm = startMinutes & 0xFFFFFFFF;
    final dm = durationMinutes & 0xFFFFF;

    final payload56 =
        (BigInt.from(v) << 52) | (BigInt.from(sm) << 20) | BigInt.from(dm);

    final checksum = _checksum8(payload56);
    final full64 = (payload56 << 8) | BigInt.from(checksum);

    final encrypted64 = _xteaEncrypt64(full64, _secret);

    final datePart = _toBase36Fixed(encrypted64, _datePartLen);
    final eventTag = _eventTagChars(eventName);

    return '$datePart$eventTag';
  }

  (DateTime, DateTime) _decodeToken(String token) {
    if (token.length != _tokenLen) {
      throw Exception('Token precisa ter $_tokenLen caracteres.');
    }

    final datePart = token.substring(0, _datePartLen);

    final encrypted64 = _fromBase36(datePart);
    final full64 = _xteaDecrypt64(encrypted64, _secret);

    final checksum = (full64 & BigInt.from(0xFF)).toInt();
    final payload56 = (full64 >> 8);

    final expected = _checksum8(payload56);
    if (checksum != expected) {
      throw Exception('Token inválido (checksum não confere).');
    }

    final v = ((payload56 >> 52) & BigInt.from(0xF)).toInt();
    if (v != _version) {
      throw Exception('Versão do token inválida: $v');
    }

    final startMinutes = ((payload56 >> 20) & BigInt.from(0xFFFFFFFF)).toInt();
    final durationMinutes = (payload56 & BigInt.from(0xFFFFF)).toInt();

    final startUtc = _baseUtc.add(Duration(minutes: startMinutes));
    final endUtc = startUtc.add(Duration(minutes: durationMinutes));

    return (startUtc.toLocal(), endUtc.toLocal());
  }

  int _checksum8(BigInt payload56) {
    final bytes7 = _bigIntToBytes(payload56, 7);
    final key = crypto.sha256.convert(_utf8(_secret)).bytes;
    final h = crypto.Hmac(crypto.sha256, key).convert(bytes7).bytes;
    return h[0] & 0xFF;
  }

  // ======================= XTEA 64-bit =======================
  BigInt _xteaEncrypt64(BigInt value64, String secret) {
    final k = _keyTo4x32(secret);

    int v0 = ((value64 >> 32) & BigInt.from(0xFFFFFFFF)).toInt();
    int v1 = (value64 & BigInt.from(0xFFFFFFFF)).toInt();

    const int delta = 0x9E3779B9;
    int sum = 0;

    v0 = _u32(v0);
    v1 = _u32(v1);

    for (int i = 0; i < 32; i++) {
      final mx0 = _u32(((_u32(v1 << 4)) ^ (v1 >>> 5)) + v1);
      v0 = _u32(v0 + (mx0 ^ _u32(sum + k[sum & 3])));

      sum = _u32(sum + delta);

      final mx1 = _u32(((_u32(v0 << 4)) ^ (v0 >>> 5)) + v0);
      v1 = _u32(v1 + (mx1 ^ _u32(sum + k[(sum >>> 11) & 3])));
    }

    return (BigInt.from(v0) << 32) | BigInt.from(v1);
  }

  BigInt _xteaDecrypt64(BigInt value64, String secret) {
    final k = _keyTo4x32(secret);

    int v0 = ((value64 >> 32) & BigInt.from(0xFFFFFFFF)).toInt();
    int v1 = (value64 & BigInt.from(0xFFFFFFFF)).toInt();

    const int delta = 0x9E3779B9;
    int sum = _u32(delta * 32);

    v0 = _u32(v0);
    v1 = _u32(v1);

    for (int i = 0; i < 32; i++) {
      final mx1 = _u32(((_u32(v0 << 4)) ^ (v0 >>> 5)) + v0);
      v1 = _u32(v1 - (mx1 ^ _u32(sum + k[(sum >>> 11) & 3])));

      sum = _u32(sum - delta);

      final mx0 = _u32(((_u32(v1 << 4)) ^ (v1 >>> 5)) + v1);
      v0 = _u32(v0 - (mx0 ^ _u32(sum + k[sum & 3])));
    }

    return (BigInt.from(v0) << 32) | BigInt.from(v1);
  }

  int _u32(int x) => x & 0xFFFFFFFF;

  List<int> _keyTo4x32(String secret) {
    final hash = crypto.sha256.convert(_utf8(secret)).bytes;
    final b = hash.sublist(0, 16);

    final w0 = _bytesToU32(b, 0);
    final w1 = _bytesToU32(b, 4);
    final w2 = _bytesToU32(b, 8);
    final w3 = _bytesToU32(b, 12);
    return [w0, w1, w2, w3];
  }

  int _bytesToU32(List<int> b, int off) {
    return ((b[off] & 0xFF) << 24) |
        ((b[off + 1] & 0xFF) << 16) |
        ((b[off + 2] & 0xFF) << 8) |
        (b[off + 3] & 0xFF);
  }

  // ======================= BASE36 =======================
  String _toBase36Fixed(BigInt value, int len) {
    if (value < BigInt.zero) throw Exception('Valor negativo.');
    BigInt n = value;
    final base = BigInt.from(36);

    if (n == BigInt.zero) return _b36[0] * len;

    final chars = <String>[];
    while (n > BigInt.zero) {
      final r = (n % base).toInt();
      chars.add(_b36[r]);
      n = n ~/ base;
    }
    final s = chars.reversed.join();

    if (s.length > len) throw Exception('Base36 excedeu $len chars.');
    return (_b36[0] * (len - s.length)) + s;
  }

  BigInt _fromBase36(String s) {
    BigInt n = BigInt.zero;
    final base = BigInt.from(36);

    final up = s.toUpperCase();
    for (int i = 0; i < up.length; i++) {
      final idx = _b36.indexOf(up[i]);
      if (idx < 0) throw Exception('Caractere inválido no token: ${up[i]}');
      n = (n * base) + BigInt.from(idx);
    }
    return n & ((BigInt.one << 64) - BigInt.one);
  }

  // ======================= BYTES HELPERS =======================
  List<int> _utf8(String s) => Uint8List.fromList(s.codeUnits);

  List<int> _bigIntToBytes(BigInt n, int length) {
    final out = List<int>.filled(length, 0);
    BigInt v = n;
    for (int i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xFF)).toInt();
      v = v >> 8;
    }
    return out;
  }

  // ======================= PICKERS =======================
  Future<void> _selectInitialDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _initialDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _initialDate) {
      setState(() {
        _initialDate = picked;
        if (_encryptedData.isNotEmpty) _updateEncryptedData();
      });
    }
  }

  Future<void> _selectFinalDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _finalDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _finalDate) {
      setState(() {
        _finalDate = picked;
        if (_encryptedData.isNotEmpty) _updateEncryptedData();
      });
    }
  }

  Future<void> _selectInitialTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _initialTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _initialTime) {
      setState(() {
        _initialTime = picked;
        if (_encryptedData.isNotEmpty) _updateEncryptedData();
      });
    }
  }

  Future<void> _selectFinalTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _finalTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _finalTime) {
      setState(() {
        _finalTime = picked;
        if (_encryptedData.isNotEmpty) _updateEncryptedData();
      });
    }
  }

  // ======================= PERMISSION + PATH (Documentos/Licencas) =======================
  Future<Directory> _getPublicDocumentsLicencasDir() async {
    if (Platform.isAndroid) {
      final perm = await Permission.manageExternalStorage.status;
      if (!perm.isGranted) {
        final req = await Permission.manageExternalStorage.request();
        if (!req.isGranted) {
          if (req.isPermanentlyDenied) {
            throw Exception(
              'Permissão negada permanentemente. Abra as configurações do app e permita "Acesso a todos os arquivos".',
            );
          }
          throw Exception('Permissão para acessar arquivos (MANAGE) negada.');
        }
      }

      final dir = Directory('/storage/emulated/0/Documents/Licencas');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Licencas');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ======================= SAVE TO DATABASE =======================
  Future<void> _saveToDatabase() async {
    setState(() => _error = '');

    if (!_eventoPreenchido) {
      setState(() => _error = 'Preencha o Nome do Evento para salvar.');
      return;
    }

    if (_encryptedData.isEmpty) {
      setState(() => _error = 'Gere o token antes de salvar.');
      return;
    }

    try {
      final dbHelper = DatabaseHelper();
      final exists = await dbHelper.tokenExists(_encryptedData);
      if (exists) {
        _showSnack('Licença já existe no banco de dados.');
        return;
      }

      final startLocal = _combineLocal(_initialDate!, _initialTime!);
      final endLocal = _combineLocal(_finalDate!, _finalTime!);

      await dbHelper.insertLicenca({
        'nome_evento': _eventoController.text.trim(),
        'data_inicial': _fmtDateTimeLocal(startLocal),
        'data_final': _fmtDateTimeLocal(endLocal),
        'token': _encryptedData,
      });

      _showSnack('Licença salva no banco de dados.');
    } catch (e) {
      setState(() => _error = 'Erro ao salvar no banco: $e');
    }
  }

  // ======================= EXPORT TO PDF (QRCode) =======================
  Future<void> _exportToPDF() async {
    setState(() => _error = '');

    if (!_eventoPreenchido) {
      setState(() => _error = 'Preencha o Nome do Evento para exportar.');
      return;
    }

    if (_encryptedData.isEmpty) {
      setState(() => _error = 'Gere o token antes de exportar.');
      return;
    }

    try {
      final licencasDir = await _getPublicDocumentsLicencasDir();

      final evento = _sanitizeFileName(_eventoController.text);
      final now = DateTime.now();
      final ts =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final fileName = 'LICENCA_${evento}_$ts.pdf';
      final file = File('${licencasDir.path}/$fileName');

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'LICENÇA DE EVENTO',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'EVENTO: ${_eventoController.text.trim().toUpperCase()}',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 10),
                pw.Text(_decodedInfo, style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 18),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _encryptedData,
                  width: 220,
                  height: 220,
                ),
                pw.SizedBox(height: 14),
                pw.Text(
                  'TOKEN: $_encryptedData',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            );
          },
        ),
      );

      await file.writeAsBytes(await pdf.save(), flush: true);

      _showSnack('PDF salvo em: ${file.path}');
      setState(() => _error = 'PDF salvo em: ${file.path}');
    } catch (e) {
      setState(() => _error = 'Erro ao exportar PDF: $e');
    }
  }

  // ======================= UI HELPERS =======================
  Widget _buildInfoBox({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  // ✅ Helper para botão expandido
  Widget _actionButton({
    required String text,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canGenerate = _eventoPreenchido;
    final bool canExport = _eventoPreenchido && _encryptedData.isNotEmpty;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: const Text('Licença - Seleção de Datas'),
          backgroundColor: Colors.blueAccent,
          actions: [
            IconButton(
              icon: const Icon(Icons.list),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LicensesScreen(),
                  ),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2.0),
            child: Container(color: Colors.white, height: 2.0),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueAccent, Colors.lightBlueAccent],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              top: 16.0,
              left: 16.0,
              right: 16.0,
              bottom: 16.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Text(
                  'Seleção de Datas',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: _eventoController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: 'Nome do Evento *',
                    hintText: 'Digite o nome do evento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {
                      if (!_eventoPreenchido) {
                        _encryptedData = '';
                        _decodedInfo = '';
                      } else {
                        if (_encryptedData.isNotEmpty) _updateEncryptedData();
                      }
                      _error = '';
                    });
                  },
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 80,
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 4,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Data Inicial',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${_initialDate != null ? '${_initialDate!.day.toString().padLeft(2, '0')}-${_initialDate!.month.toString().padLeft(2, '0')}-${_initialDate!.year}' : 'Selecione a data'} ${_initialTime != null ? _initialTime!.format(context) : 'Selecione a hora'}',
                              style: const TextStyle(color: Colors.black87),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  iconSize: 30,
                                  padding: const EdgeInsets.all(8),
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    color: Colors.blueAccent,
                                  ),
                                  onPressed: () => _selectInitialDate(context),
                                ),
                                IconButton(
                                  iconSize: 30,
                                  padding: const EdgeInsets.all(8),
                                  icon: const Icon(
                                    Icons.access_time,
                                    color: Colors.blueAccent,
                                  ),
                                  onPressed: () => _selectInitialTime(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 80,
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 4,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Data Final',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${_finalDate != null ? '${_finalDate!.day.toString().padLeft(2, '0')}-${_finalDate!.month.toString().padLeft(2, '0')}-${_finalDate!.year}' : 'Selecione a data'} ${_finalTime != null ? _finalTime!.format(context) : 'Selecione a hora'}',
                              style: const TextStyle(color: Colors.black87),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  iconSize: 30,
                                  padding: const EdgeInsets.all(8),
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    color: Colors.blueAccent,
                                  ),
                                  onPressed: () => _selectFinalDate(context),
                                ),
                                IconButton(
                                  iconSize: 30,
                                  padding: const EdgeInsets.all(8),
                                  icon: const Icon(
                                    Icons.access_time,
                                    color: Colors.blueAccent,
                                  ),
                                  onPressed: () => _selectFinalTime(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        title: 'Token (20 caracteres)',
                        child: SelectableText(
                          _encryptedData,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        title: 'Decodificado (prova de reversão)',
                        child: SelectableText(
                          _decodedInfo,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.3,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ✅ Botões em DUAS LINHAS (2 por linha)
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            text: 'Gerar Código',
                            color: Colors.grey,
                            onPressed: canGenerate
                                ? () async {
                                    setState(() {});
                                    await _updateEncryptedData();
                                    setState(() {});
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            text: 'Exportar QRCode',
                            color: Colors.black,
                            onPressed: canExport ? _exportToPDF : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            text: 'Salvar',
                            color: Colors.green,
                            onPressed: canExport ? _saveToDatabase : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            text: 'Visualizar Licenças',
                            color: Colors.purple,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LicensesScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (_error.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.redAccent),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
