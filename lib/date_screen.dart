import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _initialDate = DateTime.now();
    _finalDate = DateTime.now();
    _initialTime = const TimeOfDay(hour: 0, minute: 0);
    _finalTime = const TimeOfDay(hour: 23, minute: 59);
  }

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
      });
    }
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
        child: Padding(
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
            ],
          ),
        ),
      ),
    );
  }
}
