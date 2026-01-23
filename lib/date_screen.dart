import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart' as crypto;

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

  @override
  void initState() {
    super.initState();
    _initialDate = DateTime.now();
    _finalDate = DateTime.now();
    _initialTime = const TimeOfDay(hour: 0, minute: 0);
    _finalTime = const TimeOfDay(hour: 23, minute: 59);
    _updateEncryptedData();
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

  // ======================= EVENT TAG (4 chars) =======================
  /// TAG só pra diferenciar tokens do mesmo período com eventos diferentes.
  /// 4 chars base36 => 36^4 = 1.679.616 combinações.
  int _eventTagValue(String eventName) {
    final normalized = eventName.trim().toUpperCase();
    if (normalized.isEmpty) return 0;

    final bytes = _utf8(normalized);
    final h = crypto.sha256.convert(bytes).bytes;

    // 32 bits
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
  void _updateEncryptedData() {
    _error = '';
    _decodedInfo = '';

    if (_initialDate == null ||
        _finalDate == null ||
        _initialTime == null ||
        _finalTime == null) {
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
          'Início: ${_fmtDateTimeLocal(decoded.$1)}\nFim:    ${_fmtDateTimeLocal(decoded.$2)}';
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

    // payload 56 bits
    final payload56 =
        (BigInt.from(v) << 52) | (BigInt.from(sm) << 20) | BigInt.from(dm);

    final checksum = _checksum8(payload56);
    final full64 = (payload56 << 8) | BigInt.from(checksum);

    // Criptografa 64-bit (datas)
    final encrypted64 = _xteaEncrypt64(full64, _secret);

    // ✅ 16 chars para o bloco 64-bit criptografado
    final datePart = _toBase36Fixed(encrypted64, _datePartLen);

    // ✅ 4 chars TAG do evento (não interfere na descriptografia)
    final eventTag = _eventTagChars(eventName);

    return '$datePart$eventTag'; // total 20
  }

  /// Retorna (startLocal, endLocal)
  /// ✅ Ignora TAG do evento (últimos 4 chars)
  (DateTime, DateTime) _decodeToken(String token) {
    if (token.length != _tokenLen) {
      throw Exception('Token precisa ter $_tokenLen caracteres.');
    }

    final datePart = token.substring(0, _datePartLen);
    // final eventTag = token.substring(_datePartLen); // se quiser exibir, está aqui

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
    // HMAC-SHA256 do payload56 (7 bytes) e pega 1 byte
    final bytes7 = _bigIntToBytes(payload56, 7);
    final key = crypto.sha256.convert(_utf8(_secret)).bytes;
    final h = crypto.Hmac(crypto.sha256, key).convert(bytes7).bytes;
    return h[0] & 0xFF;
  }

  // ======================= XTEA 64-bit (FIX) =======================
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
    // Deriva 16 bytes via SHA256(secret) e usa os 16 primeiros
    final hash = crypto.sha256.convert(_utf8(secret)).bytes;
    final b = hash.sublist(0, 16);

    final w0 = _bytesToU32(b, 0);
    final w1 = _bytesToU32(b, 4);
    final w2 = _bytesToU32(b, 8);
    final w3 = _bytesToU32(b, 12);
    return [w0, w1, w2, w3];
  }

  int _bytesToU32(List<int> b, int off) {
    // big-endian
    return ((b[off] & 0xFF) << 24) |
        ((b[off + 1] & 0xFF) << 16) |
        ((b[off + 2] & 0xFF) << 8) |
        (b[off + 3] & 0xFF);
  }

  // ======================= BASE36 (MAIÚSCULO) =======================
  String _toBase36Fixed(BigInt value, int len) {
    if (value < BigInt.zero) throw Exception('Valor negativo.');
    BigInt n = value;
    final base = BigInt.from(36);

    if (n == BigInt.zero) {
      return _b36[0] * len;
    }

    final chars = <String>[];
    while (n > BigInt.zero) {
      final r = (n % base).toInt();
      chars.add(_b36[r]);
      n = n ~/ base;
    }

    final s = chars.reversed.join();

    if (s.length > len) {
      throw Exception(
        'Base36 excedeu $len chars (aumente o tamanho do token).',
      );
    }
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

    // garante 64 bits no máximo
    return n & ((BigInt.one << 64) - BigInt.one);
  }

  // ======================= BYTES HELPERS =======================
  List<int> _utf8(String s) => Uint8List.fromList(s.codeUnits);

  List<int> _bigIntToBytes(BigInt n, int length) {
    // big-endian com tamanho fixo
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
        _updateEncryptedData();
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
        _updateEncryptedData();
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
        _updateEncryptedData();
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
        _updateEncryptedData();
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: const Text('Licença - Seleção de Datas'),
          backgroundColor: Colors.blueAccent,
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

                // ✅ Nome do Evento (acima das datas)
                TextField(
                  controller: _eventoController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: 'Nome do Evento',
                    hintText: 'Digite o nome do evento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                  ),
                  onChanged: (_) => setState(() {
                    _updateEncryptedData();
                  }),
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

                // ✅ Token e Decodificado lado a lado mantendo proporções
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
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ✅ Botão abaixo dos campos Token/Decodificado
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _updateEncryptedData();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    'Gerar Código',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
