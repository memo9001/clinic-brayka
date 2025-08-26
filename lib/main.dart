import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const ClinicBraykaApp());
}

class ClinicBraykaApp extends StatelessWidget {
  const ClinicBraykaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clinic Brayka',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final pages = const [InventoryPage(), ScanPage(), AboutPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic Brayka'),
        centerTitle: true,
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.medication), label: 'المخزون'),
          NavigationDestination(icon: Icon(Icons.camera_alt), label: 'تعرف/أضف'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: 'حول'),
        ],
        onDestinationSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Medicine> items = [];
  String query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    items = await DB.instance.getAllMedicines(query: query);
    setState(() {});
  }

  void _checkThresholds() {
    for (final m in items) {
      if (m.qty <= 5) {
        NotificationService.instance.lowStock(m);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkThresholds();
    return Column(
      children: [
        Container(
          height: 140,
          width: double.infinity,
          decoration: const BoxDecoration(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/er.jpg', fit: BoxFit.cover),
              Container(color: Colors.black26),
              const Align(
                alignment: Alignment.center,
                child: Text(
                  'Clinic Brayka — Emergency',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ابحث باسم الدواء...',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) async {
              query = v;
              await _load();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (c, i) {
                final m = items[i];
                final low = m.qty <= 5;
                return Card(
                  child: ListTile(
                    leading: m.imagePath != null && m.imagePath!.isNotEmpty && File(m.imagePath!).existsSync()
                        ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(m.imagePath!), width: 48, height: 48, fit: BoxFit.cover))
                        : const Icon(Icons.medication),
                    title: Text(m.name),
                    subtitle: Text('${m.category ?? 'غير مصنف'} • الكمية: ${m.qty}'),
                    trailing: low
                        ? const Chip(label: Text('قرب ينتهي', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)
                        : const SizedBox.shrink(),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditPage(existing: m)));
                      await _load();
                    },
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صنف'),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEditPage()));
                    await _load();
                  },
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  String result = '';
  File? pickedFile;

  Future<void> _pick(ImageSource src) async {
    final img = await ImagePicker().pickImage(source: src, imageQuality: 90);
    if (img == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final targetPath = p.join(appDir.path, 'images');
    await Directory(targetPath).create(recursive: true);
    final file = File(p.join(targetPath, p.basename(img.path)));
    await File(img.path).copy(file.path);
    setState(() => pickedFile = file);
    await _runOCR(file);
  }

  Future<void> _runOCR(File file) async {
    final input = InputImage.fromFile(file);
    final recognizer = TextRecognizer();
    final RecognizedText recognizedText = await recognizer.processImage(input);
    await recognizer.close();

    String best = '';
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.length > best.length) best = text;
      }
    }
    setState(() => result = best.isEmpty ? 'لم أتعرف على اسم واضح' : best);

    if (best.isNotEmpty) {
      final existing = await DB.instance.findByName(best);
      if (existing != null) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('تم التعرف على الدواء'),
              content: Text('الاسم: ${existing.name}\\nالكمية الحالية: ${existing.qty}'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('تمام')),
              ],
            ),
          );
        }
      } else {
        if (context.mounted) {
          final goAdd = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('غير موجود بالمخزون'),
              content: Text('أضف \"$best\"؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لا')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('أضف')),
              ],
            ),
          );
          if (goAdd == true) {
            if (context.mounted) {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditPage(prefillName: best, prefillImage: pickedFile?.path)));
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: pickedFile == null
                  ? const Text('التقط صورة لعبوة الدواء أو اختر من المعرض')
                  : Image.file(pickedFile!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
          if (result.isNotEmpty) Text('نتيجة التعرف: $result'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('الكاميرا'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('المعرض'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AddEditPage extends StatefulWidget {
  final Medicine? existing;
  final String? prefillName;
  final String? prefillImage;
  const AddEditPage({super.key, this.existing, this.prefillName, this.prefillImage});

  @override
  State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController name;
  late TextEditingController category;
  late TextEditingController qty;
  String? imagePath;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.existing?.name ?? widget.prefillName ?? '');
    category = TextEditingController(text: widget.existing?.category ?? '');
    qty = TextEditingController(text: (widget.existing?.qty ?? 1).toString());
    imagePath = widget.existing?.imagePath ?? widget.prefillImage;
  }

  @override
  void dispose() {
    name.dispose();
    category.dispose();
    qty.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final targetPath = p.join(appDir.path, 'images');
    await Directory(targetPath).create(recursive: true);
    final file = File(p.join(targetPath, p.basename(img.path)));
    await File(img.path).copy(file.path);
    setState(() => imagePath = file.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final m = Medicine(
      id: widget.existing?.id,
      name: name.text.trim(),
      qty: int.tryParse(qty.text.trim()) ?? 0,
      category: category.text.trim().isEmpty ? null : category.text.trim(),
      imagePath: imagePath,
    );

    if (m.id == null) {
      await DB.instance.insertMedicine(m);
    } else {
      await DB.instance.updateMedicine(m);
    }

    if (m.qty <= 5) {
      NotificationService.instance.lowStock(m);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'إضافة صنف' : 'تعديل صنف')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم الدواء *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: category,
                decoration: const InputDecoration(labelText: 'التصنيف (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الكمية *'),
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'أدخل رقم صحيح' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.camera),
                    label: const Text('التقاط صورة'),
                  ),
                  const SizedBox(width: 12),
                  if (imagePath != null)
                    Expanded(child: Image.file(File(imagePath!), height: 120, fit: BoxFit.cover)),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('حذف الصنف؟'),
                        content: Text('سيتم حذف ${widget.existing!.name} نهائيًا'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await DB.instance.deleteMedicine(widget.existing!.id!);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف'),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset('assets/er.jpg', height: 180, fit: BoxFit.cover),
        ),
        const SizedBox(height: 16),
        const Text('Clinic Brayka', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('إدارة مخزون الأدوية بالمركز الطبي داخل القرية السياحية.'),
        const SizedBox(height: 12),
        const Text('Built by MR. Mohamed Emad', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        const Text('ملاحظات سريعة:'),
        const Text('• التعرّف بالصور يعتمد على نص العبوة (OCR). يفضل تصوير الاسم بشكل واضح.'),
        const Text('• يظهر تنبيه عندما تصل الكمية إلى 5 أو أقل.'),
      ],
    );
  }
}

class Medicine {
  final int? id;
  final String name;
  final int qty;
  final String? category;
  final String? imagePath;

  Medicine({this.id, required this.name, required this.qty, this.category, this.imagePath});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'qty': qty,
        'category': category,
        'imagePath': imagePath,
      };

  factory Medicine.fromMap(Map<String, dynamic> m) => Medicine(
        id: m['id'] as int?,
        name: m['name'] as String,
        qty: m['qty'] as int,
        category: m['category'] as String?,
        imagePath: m['imagePath'] as String?,
      );
}

class DB {
  DB._();
  static final instance = DB._();
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'clinic_brayka.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute("""
      CREATE TABLE medicines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        qty INTEGER NOT NULL,
        category TEXT,
        imagePath TEXT
      )
      """);
    });
    return _db!;
  }

  Future<List<Medicine>> getAllMedicines({String? query}) async {
    final db = await _database;
    List<Map<String, Object?>> rows;
    if (query != null && query.trim().isNotEmpty) {
      rows = await db.query('medicines', where: 'name LIKE ?', whereArgs: ['%$query%'], orderBy: 'name ASC');
    } else {
      rows = await db.query('medicines', orderBy: 'name ASC');
    }
    return rows.map((e) => Medicine.fromMap(e)).toList();
  }

  Future<Medicine?> findByName(String name) async {
    final db = await _database;
    final rows = await db.query('medicines', where: 'name = ?', whereArgs: [name]);
    if (rows.isEmpty) return null;
    return Medicine.fromMap(rows.first);
  }

  Future<int> insertMedicine(Medicine m) async {
    final db = await _database;
    return db.insert('medicines', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateMedicine(Medicine m) async {
    final db = await _database;
    return db.update('medicines', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  }

  Future<int> deleteMedicine(int id) async {
    final db = await _database;
    return db.delete('medicines', where: 'id = ?', whereArgs: [id]);
  }
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await _plugin.initialize(init);

    const channel = AndroidNotificationChannel(
      'low_stock', 'Low Stock Alerts',
      description: 'Alerts when medicine is at or below threshold', importance: Importance.high,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> lowStock(Medicine m) async {
    const androidDetails = AndroidNotificationDetails(
      'low_stock', 'Low Stock Alerts',
      importance: Importance.high, priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      m.id ?? DateTime.now().millisecondsSinceEpoch % 100000,
      'تنبيه: اقتراب نفاد الصنف',
      'الصنف \"${m.name}\" كميته ${m.qty}',
      details,
      payload: 'low_stock',
    );
  }
}
