import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _database;

  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // Дополнительный код для выхода пользователя
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    String path = '${await getDatabasesPath()}/inventory_database.db';
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _onCreate(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _onCreate(db, newVersion);
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        type TEXT,
        purchaseDate TEXT,
        nextMaintenanceDate TEXT,
        condition TEXT,
        notes TEXT,
        quantity INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS operation_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT,
        item_name TEXT,
        timestamp TEXT,
        location TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS maintenance_schedule(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_name TEXT,
        maintenanceDate TEXT,
        notes TEXT
      )
    ''');

    await _createTriggers(db);
  }

  Future<void> _createTriggers(Database db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS after_insert_inventory
      AFTER INSERT ON inventory
      BEGIN
        INSERT INTO operation_history (action, item_name, timestamp, location)
        VALUES ('add', NEW.name, DATETIME('now'), 'Основной список');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS after_delete_inventory
      AFTER DELETE ON inventory
      BEGIN
        INSERT INTO operation_history (action, item_name, timestamp, location)
        VALUES ('remove', OLD.name, DATETIME('now'), 'Основной список');
      END
    ''');
  }

  Future<int> insertInventoryItem(InventoryItem item) async {
    Database db = await database;
    return await db.insert('inventory', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateInventoryItem(InventoryItem item) async {
    Database db = await database;
    return await db.update(
      'inventory',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<InventoryItem>> getInventoryItems() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('inventory');
    return List.generate(maps.length, (i) => InventoryItem.fromMap(maps[i]));
  }

  Future<int> deleteInventoryItem(int id) async {
    Database db = await database;
    return await db.delete('inventory', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllInventoryItems() async {
    Database db = await database;
    return await db.delete('inventory');
  }

  Future<bool> itemExists(String name) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'inventory',
      where: 'name = ?',
      whereArgs: [name],
    );
    return maps.isNotEmpty;
  }

  Future<int> insertHistoryItem(HistoryItem item) async {
    Database db = await database;
    return await db.insert('operation_history', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<HistoryItem>> getHistoryItems() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('operation_history');
    return List.generate(maps.length, (i) => HistoryItem.fromMap(maps[i]));
  }

  Future<int> deleteHistoryItem(int id) async {
    Database db = await database;
    return await db.delete('operation_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearHistory() async {
    Database db = await database;
    return await db.delete('operation_history');
  }

  Future<int> insertMaintenanceSchedule(MaintenanceScheduleItem item) async {
    Database db = await database;
    return await db.insert('maintenance_schedule', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MaintenanceScheduleItem>> getMaintenanceSchedule() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('maintenance_schedule');
    return List.generate(maps.length, (i) => MaintenanceScheduleItem.fromMap(maps[i]));
  }

  Future<int> deleteMaintenanceScheduleItem(int id) async {
    Database db = await database;
    return await db.delete('maintenance_schedule', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearMaintenanceSchedule() async {
    Database db = await database;
    return await db.delete('maintenance_schedule');
  }

  Future<List<InventoryItem>> getItemsNeedingMaintenance() async {
    Database db = await database;
    DateTime now = DateTime.now();
    String nowFormatted = DateFormat('yyyy-MM-dd').format(now);

    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT * FROM inventory 
      WHERE nextMaintenanceDate <= '$nowFormatted'
    ''');

    return List.generate(maps.length, (i) => InventoryItem.fromMap(maps[i]));
  }

  // Method to clear all data
  Future<void> clearAllData() async {
    Database db = await database;
    await db.delete('inventory');
    await db.delete('operation_history');
    await db.delete('maintenance_schedule');

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

class InventoryItem {
  int? id;
  String name;
  String type;
  String purchaseDate;
  String nextMaintenanceDate;
  String condition;
  String notes;
  int quantity;

  InventoryItem({
    this.id,
    required this.name,
    required this.type,
    required this.purchaseDate,
    required this.nextMaintenanceDate,
    required this.condition,
    required this.notes,
    this.quantity = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'purchaseDate': purchaseDate,
      'nextMaintenanceDate': nextMaintenanceDate,
      'condition': condition,
      'notes': notes,
      'quantity': quantity,
    };
  }

  static InventoryItem fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'],
      name: map['name'],
      type: map['type'],
      purchaseDate: map['purchaseDate'],
      nextMaintenanceDate: map['nextMaintenanceDate'],
      condition: map['condition'],
      notes: map['notes'],
      quantity: map['quantity'] ?? 1,
    );
  }
}

class MaintenanceScheduleItem {
  int? id;
  String itemName;
  String maintenanceDate;
  String notes;

  MaintenanceScheduleItem({
    this.id,
    required this.itemName,
    required this.maintenanceDate,
    required this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_name': itemName,
      'maintenanceDate': maintenanceDate,
      'notes': notes,
    };
  }

  static MaintenanceScheduleItem fromMap(Map<String, dynamic> map) {
    return MaintenanceScheduleItem(
      id: map['id'],
      itemName: map['item_name'],
      maintenanceDate: map['maintenanceDate'],
      notes: map['notes'],
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Поиск инвентаря',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: InventoryScreen(),
    );
  }
}

class InventoryScreen extends StatefulWidget {
  @override
  _InventoryScreenState createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with WidgetsBindingObserver {
  List<InventoryItem> _inventoryItems = [];
  List<HistoryItem> _historyItems = [];
  String _searchQuery = '';
  bool _isSearching = false;
  DatabaseHelper dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadInventoryItems();
    _loadHistory();
    WidgetsBinding.instance.addObserver(this);
  }

  List<InventoryItem> _getFilteredItems() {
    return _inventoryItems.where((item) =>
        item.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  Future<void> _scanQR() async {
    String barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
      '#ff6666',
      'Отмена',
      true,
      ScanMode.QR,
    );
    if (barcodeScanRes != '-1') {
      Map<String, dynamic> itemData = json.decode(barcodeScanRes);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultPage(
            scanResult: itemData,
            onConfirm: () => _addInventoryItem(itemData),
          ),
        ),
      );
    }
  }

  void _addInventoryItem(Map<String, dynamic> itemData) {
    setState(() {
      InventoryItem newItem = InventoryItem(
        name: itemData['name'],
        type: itemData['type'],
        purchaseDate: itemData['purchaseDate'],
        nextMaintenanceDate: itemData['nextMaintenanceDate'],
        condition: itemData['condition'],
        notes: itemData['notes'],
        quantity: 1,
      );

      dbHelper.insertInventoryItem(newItem);
      _inventoryItems.add(newItem);

      _addHistoryItem(HistoryItem(
        action: 'add',
        itemName: newItem.name,
        timestamp: DateTime.now(),
        location: 'Основной список',
      ));
    });
    _saveInventoryItems();
  }

  void _deleteInventoryItem(InventoryItem item) {
    setState(() {
      dbHelper.deleteInventoryItem(item.id!);
      _inventoryItems.remove(item);

      _addHistoryItem(HistoryItem(
        action: 'remove',
        itemName: item.name,
        timestamp: DateTime.now(),
        location: 'Основной список',
      ));
    });
    _saveInventoryItems();
  }

  Future<void> _loadInventoryItems() async {
    _inventoryItems = await dbHelper.getInventoryItems();
    setState(() {});
  }

  Future<void> _saveInventoryItems() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final encodedItems = jsonEncode(_inventoryItems.map((item) => item.toMap()).toList());
    await prefs.setString('inventory', encodedItems);
  }

  void _saveHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> historyJson = _historyItems.map((item) => jsonEncode(item.toMap())).toList();
    await prefs.setString('history', historyJson as String);
  }

  void _loadHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? historyJson = prefs.getStringList('history');
    if (historyJson != null) {
      setState(() {
        _historyItems = historyJson.map((item) => HistoryItem.fromMap(jsonDecode(item))).toList();
      });
    }
  }

  void _addHistoryItem(HistoryItem item) {
    setState(() {
      _historyItems.add(item);
    });
    _saveHistory();
  }

  String _getDaysUntilMaintenance(String maintenanceDateStr) {
    DateTime maintenanceDate = DateTime.parse(maintenanceDateStr);
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    int remainingDays = maintenanceDate.difference(today).inDays;

    if (remainingDays < 0) {
      return 'Требуется ТО';
    } else if (remainingDays == 0) {
      return 'ТО сегодня';
    } else {
      return '${remainingDays} дн. до ТО';
    }
  }

  // Method to show the clear data confirmation dialog
  /*Future<void> _showClearDataConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Подтверждение очистки данных'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Вы уверены, что хотите удалить все данные?'),
                Text('Это действие нельзя будет отменить.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Очистить', style: TextStyle(color: Colors.red)),
              onPressed: () {
                _clearAllData();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Method to clear all data
  Future<void> _clearAllData() async {
    await dbHelper.clearAllData();
    setState(() {
      _inventoryItems.clear();
      _historyItems.clear();
    });
  }*/

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Поиск инвентаря...',
            border: InputBorder.none,
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        )
            : Text('Инвентарь'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                }
              });
            },
          ),
        ],
      ),
      body: _searchQuery.isEmpty
          ? ListView.builder(
        itemCount: _inventoryItems.length,
        itemBuilder: (context, index) {
          final item = _inventoryItems[index];
          String maintenanceStatus = _getDaysUntilMaintenance(item.nextMaintenanceDate);

          return Dismissible(
            key: UniqueKey(),
            background: Container(
              color: Colors.red,
              child: Icon(Icons.delete, color: Colors.white),
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 20),
            ),
            direction: DismissDirection.endToStart,
            onDismissed: (direction) {
              _deleteInventoryItem(item);
            },
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(item.name)),
                  Text(
                    maintenanceStatus,
                    style: TextStyle(
                      color: maintenanceStatus == 'Требуется ТО' ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              subtitle: Text('Тип: ${item.type}'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ItemDetailsPage(item: item),
                  ),
                );
              },
              trailing: IconButton(
                icon: Icon(Icons.delete),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text('Удалить инвентарь'),
                        content: Text('Вы уверены, что хотите удалить ${item.name}?'),
                        actions: <Widget>[
                          TextButton(
                            child: Text('Отмена'),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                          TextButton(
                            child: Text('Удалить'),
                            onPressed: () {
                              _deleteInventoryItem(item);
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      )
          : ListView.builder(
        itemCount: _getFilteredItems().length,
        itemBuilder: (context, index) {
          final item = _getFilteredItems()[index];
          String maintenanceStatus = _getDaysUntilMaintenance(item.nextMaintenanceDate);
          return ListTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(item.name)),
                Text(
                  maintenanceStatus,
                  style: TextStyle(
                    color: maintenanceStatus == 'Требуется ТО' ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            subtitle: Text('Тип: ${item.type}'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ItemDetailsPage(item: item),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: BottomAppBar(
        shape: CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: Icon(Icons.qr_code_scanner),
              onPressed: _scanQR,
              tooltip: 'Сканировать QR-код',
            ),
            IconButton(
              icon: Icon(Icons.build),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => MaintenanceSelectionPage(
                    onMaintenanceCompleted: () {
                      _loadInventoryItems();
                      _loadHistory();
                    },
                  )),
                );
              },
              tooltip: 'Тех. Обслуживание',
            ),
            IconButton(
              icon: Icon(Icons.history),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => HistoryPage(historyItems: _historyItems)),
                );
              },
              tooltip: 'История',
            ),
            // Add the clear data button
            /*IconButton(
              icon: Icon(Icons.delete_forever, color: Colors.red),
              onPressed: _showClearDataConfirmationDialog,
              tooltip: 'Очистить все данные',
            ),*/
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveInventoryItems();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveInventoryItems();
    }
  }
}

class ResultPage extends StatelessWidget {
  final Map<String, dynamic> scanResult;
  final Function onConfirm;

  ResultPage({required this.scanResult, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Результат сканирования'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Детали инвентаря:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Table(
                border: TableBorder.all(),
                children: scanResult.entries.map((entry) {
                  return TableRow(
                    children: [
                      TableCell(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      TableCell(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(entry.value.toString()),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    onConfirm();
                    Navigator.pop(context);
                  },
                  child: Text('Добавить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemDetailsPage extends StatelessWidget {
  final InventoryItem item;

  ItemDetailsPage({required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Table(
            border: TableBorder.all(),
            children: [
              _buildTableRow('Название', item.name),
              _buildTableRow('Тип', item.type),
              _buildTableRow('Последнее ТО', DateFormat('dd.MM.yyyy').format(DateTime.parse(item.purchaseDate))),
              _buildTableRow('Следующее ТО', DateFormat('dd.MM.yyyy').format(DateTime.parse(item.nextMaintenanceDate))),
              _buildTableRow('Состояние', item.condition),
              _buildTableRow('Заметки', item.notes),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _buildTableRow(String title, String value) {
    return TableRow(
      children: [
        TableCell(child: Padding(padding: const EdgeInsets.all(8.0), child: Text(title, style: TextStyle(fontWeight: FontWeight.bold)))),
        TableCell(child: Padding(padding: const EdgeInsets.all(8.0), child: Text(value))),
      ],
    );
  }
}

class MaintenanceSelectionPage extends StatefulWidget {
  final VoidCallback onMaintenanceCompleted;

  MaintenanceSelectionPage({Key? key, required this.onMaintenanceCompleted}) : super(key: key);

  @override
  _MaintenanceSelectionPageState createState() => _MaintenanceSelectionPageState();
}

class _MaintenanceSelectionPageState extends State<MaintenanceSelectionPage> {
  DatabaseHelper dbHelper = DatabaseHelper();
  List<InventoryItem> _itemsNeedingMaintenance = [];

  @override
  void initState() {
    super.initState();
    _loadItemsNeedingMaintenance();
  }

  Future<void> _loadItemsNeedingMaintenance() async {
    _itemsNeedingMaintenance = await dbHelper.getItemsNeedingMaintenance();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Выбор инвентаря для ТО'),
      ),
      body: _itemsNeedingMaintenance.isEmpty
          ? Center(child: Text('Нет инвентаря, требующего ТО.'))
          : ListView.builder(
        itemCount: _itemsNeedingMaintenance.length,
        itemBuilder: (context, index) {
          final item = _itemsNeedingMaintenance[index];
          return ListTile(
            title: Text(item.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PerformMaintenancePage(item: item,
                            onMaintenancePerformed: _updateMaintenanceDate,
                            onMaintenanceCompleted: widget
                                .onMaintenanceCompleted),
                      ),
                    );
                  },
                  child: Text('Провести ТО'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _showDisposalConfirmationDialog(item);
                  },
                  child: Text('Утилизировать'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDisposalConfirmationDialog(InventoryItem item) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Подтверждение утилизации'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Вы уверены, что хотите утилизировать ${item.name}?'),
                Text('Это действие нельзя будет отменить.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text(
                  'Утилизировать', style: TextStyle(color: Colors.red)),
              onPressed: () {
                _disposeItem(item);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _disposeItem(InventoryItem item) {
    // Implement disposal logic here
    DatabaseHelper dbHelper = DatabaseHelper();
    dbHelper.deleteInventoryItem(item.id!);

    setState(() {
      _itemsNeedingMaintenance.remove(item);
    });
  }

  void _updateMaintenanceDate(InventoryItem item, DateTime newDate) {
    DatabaseHelper dbHelper = DatabaseHelper();

    DateTime lastMaintenanceDate = DateTime(
        newDate.year - 1, newDate.month, newDate.day);

    setState(() {
      item.nextMaintenanceDate = DateFormat('yyyy-MM-dd').format(newDate);
      item.purchaseDate = DateFormat('yyyy-MM-dd').format(
          lastMaintenanceDate); // Update lastMaintenanceDate
      dbHelper.updateInventoryItem(item);
      _loadItemsNeedingMaintenance(); // Refresh the list
    });
  }
}

  class PerformMaintenancePage extends StatefulWidget {
  final InventoryItem item;
  final Function(InventoryItem, DateTime) onMaintenancePerformed;
  final VoidCallback onMaintenanceCompleted;

  PerformMaintenancePage({Key? key, required this.item, required this.onMaintenancePerformed, required this.onMaintenanceCompleted}) : super(key: key);

  @override
  _PerformMaintenancePageState createState() => _PerformMaintenancePageState();
}

class _PerformMaintenancePageState extends State<PerformMaintenancePage> {
  TextEditingController _maintenanceNotesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate)
      setState(() {
        _selectedDate = picked;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Проведение ТО'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Инвентарь: ${widget.item.name}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('Дата проведения ТО:'),
            Row(
              children: [
                Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
                IconButton(
                  icon: Icon(Icons.calendar_today),
                  onPressed: () => _selectDate(context),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              controller: _maintenanceNotesController,
              decoration: InputDecoration(
                hintText: 'Заметки о ТО',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                _saveMaintenanceInfo();
              },
              child: Text('Сохранить ТО'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveMaintenanceInfo() {
    // Save the maintenance information to the database or shared preferences
    DatabaseHelper dbHelper = DatabaseHelper();
    MaintenanceScheduleItem newItem = MaintenanceScheduleItem(
      itemName: widget.item.name,
      maintenanceDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
      notes: _maintenanceNotesController.text,
    );
    dbHelper.insertMaintenanceSchedule(newItem);

    // Update the next maintenance date in the inventory
    DateTime nextMaintenanceDate = _selectedDate.add(Duration(days: 365));
    widget.onMaintenancePerformed(widget.item, nextMaintenanceDate);

    // Pop the current screen and call the onMaintenanceCompleted callback
    Navigator.pop(context);
    widget.onMaintenanceCompleted();
  }
}

class HistoryPage extends StatefulWidget {
  final List<HistoryItem> historyItems;

  HistoryPage({required this.historyItems});

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime _startDate = DateTime.now().subtract(Duration(days: 7));
  DateTime _endDate = DateTime.now();
  List<HistoryItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filterItems();
  }

  void _filterItems() {
    setState(() {
      _filteredItems = widget.historyItems.where((item) =>
      item.timestamp.isAfter(_startDate.subtract(Duration(days: 1))) &&
          item.timestamp.isBefore(_endDate.add(Duration(days: 1)))
      ).toList();
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _filterItems();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('История'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Период: ${DateFormat('dd.MM.yyyy').format(_startDate)} - ${DateFormat('dd.MM.yyyy').format(_endDate)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return ListTile(
                  leading: Icon(
                    item.action == 'add' ? Icons.add_circle : Icons.remove_circle,
                    color: item.action == 'add' ? Colors.green : Colors.red,
                  ),
                  title: Text(item.itemName),
                  subtitle: Text('${item.action == 'add' ? 'Добавлено' : 'Удалено'} ${DateFormat('dd.MM.yyyy HH:mm').format(item.timestamp)}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryItem {
  final String action;
  final String itemName;
  final DateTime timestamp;
  final String location;

  HistoryItem({
    required this.action,
    required this.itemName,
    required this.timestamp,
    required this.location,
  });

  Map<String, dynamic> toMap() {
    return {
      'action': action,
      'item_name': itemName,
      'timestamp': timestamp.toIso8601String(),
      'location': location,
    };
  }

  static HistoryItem fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      action: map['action'],
      itemName: map['item_name'],
      timestamp: DateTime.parse(map['timestamp']),
      location: map['location'],
    );
  }
}
