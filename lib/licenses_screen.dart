import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'database_helper.dart';

class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  List<Map<String, dynamic>> _licenses = [];

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  Future<void> _loadLicenses() async {
    final dbHelper = DatabaseHelper();
    final licenses = await dbHelper.queryAllLicencas();
    setState(() {
      _licenses = licenses;
    });
  }

  Future<void> _deleteLicense(int id) async {
    final dbHelper = DatabaseHelper();
    await dbHelper.deleteLicenca(id);
    _loadLicenses(); // Reload the list
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Licença excluída.')));
  }

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

  Future<void> _exportLicenseToPDF(Map<String, dynamic> license) async {
    try {
      final licencasDir = await _getPublicDocumentsLicencasDir();

      final evento = license['nome_evento'].toString().replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
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
                  'EVENTO: ${license['nome_evento'].toString().toUpperCase()}',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Data Inicial: ${license['data_inicial']}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Text(
                  'Data Final: ${license['data_final']}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 18),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: license['token'],
                  width: 220,
                  height: 220,
                ),
                pw.SizedBox(height: 14),
                pw.Text(
                  'TOKEN: ${license['token']}',
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF salvo em: ${file.path}')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao exportar PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Licenças Criadas'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueAccent, Colors.lightBlueAccent],
          ),
        ),
        child: _licenses.isEmpty
            ? const Center(
                child: Text(
                  'Nenhuma licença criada.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              )
            : ListView.builder(
                itemCount: _licenses.length,
                itemBuilder: (context, index) {
                  final license = _licenses[index];
                  return Card(
                    margin: const EdgeInsets.all(8.0),
                    child: ListTile(
                      title: Text(
                        'Evento: ${license['nome_evento']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Data Inicial: ${license['data_inicial']}'),
                          Text('Data Final: ${license['data_final']}'),
                          Text('Token: ${license['token']}'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.picture_as_pdf,
                              color: Colors.green,
                            ),
                            onPressed: () => _exportLicenseToPDF(license),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteLicense(license['id']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
