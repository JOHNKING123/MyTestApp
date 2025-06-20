# Flutter 语法参考文档

## 目录
- [Dart 语言基础](#dart-语言基础)
- [Flutter 框架核心](#flutter-框架核心)
- [常用 Widget](#常用-widget)
- [状态管理](#状态管理)
- [导航和路由](#导航和路由)
- [网络请求](#网络请求)
- [本地存储](#本地存储)
- [最佳实践](#最佳实践)

---

## Dart 语言基础

### 1. 变量声明

```dart
// 变量声明
var name = 'Flutter';           // 类型推断
String title = 'Hello';         // 显式类型声明
final pi = 3.14;               // 运行时常量
const gravity = 9.8;           // 编译时常量
late String description;       // 延迟初始化

// 空安全
String? nullableString;        // 可空类型
String nonNullableString = ''; // 非空类型
```

### 2. 数据类型

```dart
// 基本类型
int count = 42;
double price = 19.99;
bool isActive = true;
String message = 'Hello World';

// 集合类型
List<String> fruits = ['apple', 'banana', 'orange'];
Map<String, dynamic> user = {
  'name': 'John',
  'age': 25,
  'email': 'john@example.com'
};
Set<int> numbers = {1, 2, 3, 4, 5};

// 动态类型
dynamic dynamicValue = 'anything';
var inferredType = 'string'; // 推断为 String
```

### 3. 函数

```dart
// 基本函数
void sayHello() {
  print('Hello!');
}

// 带参数的函数
String greet(String name) {
  return 'Hello, $name!';
}

// 可选参数
void printInfo(String name, {int? age, String? city}) {
  print('Name: $name');
  if (age != null) print('Age: $age');
  if (city != null) print('City: $city');
}

// 默认参数
void createUser(String name, {String role = 'user'}) {
  print('Created user: $name with role: $role');
}

// 箭头函数
int add(int a, int b) => a + b;

// 函数作为参数
void processData(Function callback) {
  callback('processed data');
}
```

### 4. 类

```dart
// 基本类
class Person {
  // 属性
  String name;
  int age;
  
  // 构造函数
  Person(this.name, this.age);
  
  // 命名构造函数
  Person.guest() : name = 'Guest', age = 0;
  
  // 方法
  void introduce() {
    print('Hi, I\'m $name and I\'m $age years old');
  }
  
  // Getter
  String get info => '$name ($age)';
  
  // Setter
  set setAge(int newAge) {
    if (newAge >= 0) age = newAge;
  }
}

// 继承
class Student extends Person {
  String school;
  
  Student(String name, int age, this.school) : super(name, age);
  
  @override
  void introduce() {
    super.introduce();
    print('I study at $school');
  }
}

// 抽象类
abstract class Animal {
  void makeSound();
}

class Dog extends Animal {
  @override
  void makeSound() {
    print('Woof!');
  }
}
```

### 5. 异步编程

```dart
// Future
Future<String> fetchData() async {
  await Future.delayed(Duration(seconds: 2));
  return 'Data loaded';
}

// 使用 Future
void loadData() async {
  try {
    String data = await fetchData();
    print(data);
  } catch (e) {
    print('Error: $e');
  }
}

// Stream
Stream<int> countStream() async* {
  for (int i = 1; i <= 5; i++) {
    await Future.delayed(Duration(seconds: 1));
    yield i;
  }
}

// 使用 Stream
void listenToStream() {
  countStream().listen(
    (data) => print('Received: $data'),
    onError: (error) => print('Error: $error'),
    onDone: () => print('Stream completed'),
  );
}
```

---

## Flutter 框架核心

### 1. Widget 基础

```dart
// StatelessWidget - 无状态组件
class MyWidget extends StatelessWidget {
  final String title;
  
  const MyWidget({Key? key, required this.title}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text(title),
    );
  }
}

// StatefulWidget - 有状态组件
class CounterWidget extends StatefulWidget {
  @override
  _CounterWidgetState createState() => _CounterWidgetState();
}

class _CounterWidgetState extends State<CounterWidget> {
  int count = 0;
  
  void increment() {
    setState(() {
      count++;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Count: $count'),
        ElevatedButton(
          onPressed: increment,
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

### 2. 布局 Widget

```dart
// Column - 垂直布局
Column(
  children: [
    Text('Item 1'),
    Text('Item 2'),
    Text('Item 3'),
  ],
)

// Row - 水平布局
Row(
  children: [
    Icon(Icons.star),
    Text('Rating: 4.5'),
  ],
)

// Stack - 层叠布局
Stack(
  children: [
    Container(
      width: 200,
      height: 200,
      color: Colors.blue,
    ),
    Positioned(
      top: 10,
      left: 10,
      child: Text('Overlay Text'),
    ),
  ],
)

// Wrap - 自动换行
Wrap(
  spacing: 8.0,
  runSpacing: 4.0,
  children: [
    Chip(label: Text('Tag 1')),
    Chip(label: Text('Tag 2')),
    Chip(label: Text('Tag 3')),
  ],
)
```

### 3. 容器 Widget

```dart
// Container - 通用容器
Container(
  width: 100,
  height: 100,
  margin: EdgeInsets.all(8.0),
  padding: EdgeInsets.all(16.0),
  decoration: BoxDecoration(
    color: Colors.blue,
    borderRadius: BorderRadius.circular(8.0),
    boxShadow: [
      BoxShadow(
        color: Colors.grey.withOpacity(0.5),
        spreadRadius: 2,
        blurRadius: 5,
        offset: Offset(0, 3),
      ),
    ],
  ),
  child: Text('Hello'),
)

// Card - 卡片容器
Card(
  elevation: 4.0,
  child: Padding(
    padding: EdgeInsets.all(16.0),
    child: Column(
      children: [
        Text('Card Title'),
        Text('Card content'),
      ],
    ),
  ),
)
```

---

## 常用 Widget

### 1. 文本 Widget

```dart
// Text
Text(
  'Hello World',
  style: TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
    color: Colors.blue,
  ),
)

// RichText
RichText(
  text: TextSpan(
    style: TextStyle(color: Colors.black),
    children: [
      TextSpan(text: 'Hello '),
      TextSpan(
        text: 'World',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    ],
  ),
)
```

### 2. 按钮 Widget

```dart
// ElevatedButton
ElevatedButton(
  onPressed: () {
    print('Button pressed');
  },
  child: Text('Click Me'),
)

// TextButton
TextButton(
  onPressed: () {
    print('Text button pressed');
  },
  child: Text('Text Button'),
)

// IconButton
IconButton(
  onPressed: () {
    print('Icon pressed');
  },
  icon: Icon(Icons.favorite),
  color: Colors.red,
)
```

### 3. 输入 Widget

```dart
// TextField
TextField(
  decoration: InputDecoration(
    labelText: 'Enter your name',
    hintText: 'John Doe',
    border: OutlineInputBorder(),
  ),
  onChanged: (value) {
    print('Input: $value');
  },
)

// TextFormField (带验证)
TextFormField(
  decoration: InputDecoration(
    labelText: 'Email',
    border: OutlineInputBorder(),
  ),
  validator: (value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!value.contains('@')) {
      return 'Please enter a valid email';
    }
    return null;
  },
)
```

### 4. 图片 Widget

```dart
// Image.network
Image.network(
  'https://example.com/image.jpg',
  width: 200,
  height: 200,
  fit: BoxFit.cover,
  loadingBuilder: (context, child, loadingProgress) {
    if (loadingProgress == null) return child;
    return CircularProgressIndicator();
  },
)

// Image.asset
Image.asset(
  'assets/images/logo.png',
  width: 100,
  height: 100,
)

// CircleAvatar
CircleAvatar(
  radius: 50,
  backgroundImage: NetworkImage('https://example.com/avatar.jpg'),
)
```

### 5. 列表 Widget

```dart
// ListView
ListView(
  children: [
    ListTile(
      leading: Icon(Icons.person),
      title: Text('John Doe'),
      subtitle: Text('john@example.com'),
      trailing: Icon(Icons.arrow_forward),
      onTap: () {
        print('Tapped on John Doe');
      },
    ),
    ListTile(
      leading: Icon(Icons.person),
      title: Text('Jane Smith'),
      subtitle: Text('jane@example.com'),
      trailing: Icon(Icons.arrow_forward),
    ),
  ],
)

// ListView.builder (动态列表)
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return ListTile(
      title: Text(items[index].title),
      subtitle: Text(items[index].subtitle),
    );
  },
)
```

---

## 状态管理

### 1. setState (简单状态管理)

```dart
class CounterWidget extends StatefulWidget {
  @override
  _CounterWidgetState createState() => _CounterWidgetState();
}

class _CounterWidgetState extends State<CounterWidget> {
  int count = 0;
  
  void increment() {
    setState(() {
      count++;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Count: $count'),
        ElevatedButton(
          onPressed: increment,
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

### 2. Provider (推荐的状态管理)

```dart
// 首先添加依赖到 pubspec.yaml
// provider: ^6.0.0

// 创建数据模型
class CounterModel extends ChangeNotifier {
  int _count = 0;
  
  int get count => _count;
  
  void increment() {
    _count++;
    notifyListeners();
  }
  
  void decrement() {
    _count--;
    notifyListeners();
  }
}

// 在 main.dart 中设置 Provider
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => CounterModel(),
      child: MyApp(),
    ),
  );
}

// 在 Widget 中使用
class CounterWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<CounterModel>(
      builder: (context, counter, child) {
        return Column(
          children: [
            Text('Count: ${counter.count}'),
            ElevatedButton(
              onPressed: () => counter.increment(),
              child: Text('Increment'),
            ),
          ],
        );
      },
    );
  }
}
```

### 3. Bloc (复杂状态管理)

```dart
// 首先添加依赖到 pubspec.yaml
// flutter_bloc: ^8.0.0

// 定义事件
abstract class CounterEvent {}

class IncrementEvent extends CounterEvent {}
class DecrementEvent extends CounterEvent {}

// 定义状态
abstract class CounterState {
  final int count;
  CounterState(this.count);
}

class CounterInitial extends CounterState {
  CounterInitial() : super(0);
}

class CounterUpdated extends CounterState {
  CounterUpdated(int count) : super(count);
}

// 定义 Bloc
class CounterBloc extends Bloc<CounterEvent, CounterState> {
  CounterBloc() : super(CounterInitial()) {
    on<IncrementEvent>((event, emit) {
      emit(CounterUpdated(state.count + 1));
    });
    
    on<DecrementEvent>((event, emit) {
      emit(CounterUpdated(state.count - 1));
    });
  }
}

// 在 Widget 中使用
class CounterWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CounterBloc(),
      child: BlocBuilder<CounterBloc, CounterState>(
        builder: (context, state) {
          return Column(
            children: [
              Text('Count: ${state.count}'),
              ElevatedButton(
                onPressed: () {
                  context.read<CounterBloc>().add(IncrementEvent());
                },
                child: Text('Increment'),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

---

## 导航和路由

### 1. 基本导航

```dart
// 导航到新页面
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => SecondPage(),
  ),
);

// 返回上一页
Navigator.pop(context);

// 导航并替换当前页面
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => NewPage(),
  ),
);

// 导航到新页面并清除所有路由
Navigator.pushAndRemoveUntil(
  context,
  MaterialPageRoute(
    builder: (context) => HomePage(),
  ),
  (route) => false,
);
```

### 2. 命名路由

```dart
// 在 MaterialApp 中定义路由
MaterialApp(
  initialRoute: '/',
  routes: {
    '/': (context) => HomePage(),
    '/second': (context) => SecondPage(),
    '/third': (context) => ThirdPage(),
  },
);

// 使用命名路由导航
Navigator.pushNamed(context, '/second');

// 带参数的路由
Navigator.pushNamed(
  context,
  '/detail',
  arguments: {'id': 123, 'title': 'Detail Page'},
);

// 在目标页面接收参数
class DetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final id = args['id'];
    final title = args['title'];
    
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Text('ID: $id'),
    );
  }
}
```

### 3. 路由守卫

```dart
// 检查用户是否已登录
class AuthGuard {
  static bool isLoggedIn = false;
  
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (!isLoggedIn && settings.name != '/login') {
      return MaterialPageRoute(
        builder: (context) => LoginPage(),
      );
    }
    
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (context) => HomePage());
      case '/profile':
        return MaterialPageRoute(builder: (context) => ProfilePage());
      default:
        return MaterialPageRoute(builder: (context) => NotFoundPage());
    }
  }
}

// 在 MaterialApp 中使用
MaterialApp(
  onGenerateRoute: AuthGuard.onGenerateRoute,
);
```

---

## 网络请求

### 1. HTTP 请求 (http 包)

```dart
// 首先添加依赖到 pubspec.yaml
// http: ^0.13.0

import 'package:http/http.dart' as http;
import 'dart:convert';

// GET 请求
Future<Map<String, dynamic>> fetchData() async {
  final response = await http.get(
    Uri.parse('https://api.example.com/data'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer your_token',
    },
  );
  
  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    throw Exception('Failed to load data');
  }
}

// POST 请求
Future<Map<String, dynamic>> createPost(String title, String body) async {
  final response = await http.post(
    Uri.parse('https://api.example.com/posts'),
    headers: {
      'Content-Type': 'application/json',
    },
    body: json.encode({
      'title': title,
      'body': body,
    }),
  );
  
  if (response.statusCode == 201) {
    return json.decode(response.body);
  } else {
    throw Exception('Failed to create post');
  }
}

// 在 Widget 中使用
class DataWidget extends StatefulWidget {
  @override
  _DataWidgetState createState() => _DataWidgetState();
}

class _DataWidgetState extends State<DataWidget> {
  Map<String, dynamic>? data;
  bool isLoading = true;
  
  @override
  void initState() {
    super.initState();
    loadData();
  }
  
  Future<void> loadData() async {
    try {
      final result = await fetchData();
      setState(() {
        data = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return CircularProgressIndicator();
    }
    
    if (data == null) {
      return Text('Failed to load data');
    }
    
    return Text('Data: ${data!['title']}');
  }
}
```

### 2. Dio (更强大的 HTTP 客户端)

```dart
// 首先添加依赖到 pubspec.yaml
// dio: ^5.0.0

import 'package:dio/dio.dart';

// 创建 Dio 实例
final dio = Dio(BaseOptions(
  baseUrl: 'https://api.example.com',
  connectTimeout: Duration(seconds: 5),
  receiveTimeout: Duration(seconds: 3),
));

// 添加拦截器
dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) {
    print('Request: ${options.method} ${options.path}');
    handler.next(options);
  },
  onResponse: (response, handler) {
    print('Response: ${response.statusCode}');
    handler.next(response);
  },
  onError: (error, handler) {
    print('Error: ${error.message}');
    handler.next(error);
  },
));

// 使用 Dio 发送请求
Future<Map<String, dynamic>> fetchData() async {
  try {
    final response = await dio.get('/data');
    return response.data;
  } on DioException catch (e) {
    throw Exception('Network error: ${e.message}');
  }
}
```

---

## 本地存储

### 1. SharedPreferences (简单数据存储)

```dart
// 首先添加依赖到 pubspec.yaml
// shared_preferences: ^2.0.0

import 'package:shared_preferences/shared_preferences.dart';

// 保存数据
Future<void> saveData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('username', 'john_doe');
  await prefs.setInt('age', 25);
  await prefs.setBool('isLoggedIn', true);
  await prefs.setStringList('favorites', ['item1', 'item2']);
}

// 读取数据
Future<void> loadData() async {
  final prefs = await SharedPreferences.getInstance();
  final username = prefs.getString('username');
  final age = prefs.getInt('age');
  final isLoggedIn = prefs.getBool('isLoggedIn');
  final favorites = prefs.getStringList('favorites');
  
  print('Username: $username');
  print('Age: $age');
  print('Is Logged In: $isLoggedIn');
  print('Favorites: $favorites');
}

// 删除数据
Future<void> clearData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}
```

### 2. SQLite (数据库存储)

```dart
// 首先添加依赖到 pubspec.yaml
// sqflite: ^2.0.0
// path: ^1.8.0

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// 数据库助手类
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'my_database.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL
      )
    ''');
  }
  
  // 插入用户
  Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await database;
    return await db.insert('users', user);
  }
  
  // 查询所有用户
  Future<List<Map<String, dynamic>>> getUsers() async {
    final db = await database;
    return await db.query('users');
  }
  
  // 更新用户
  Future<int> updateUser(Map<String, dynamic> user) async {
    final db = await database;
    return await db.update(
      'users',
      user,
      where: 'id = ?',
      whereArgs: [user['id']],
    );
  }
  
  // 删除用户
  Future<int> deleteUser(int id) async {
    final db = await database;
    return await db.delete(
      'users',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

// 使用示例
class UserService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  Future<void> addUser(String name, String email) async {
    await _dbHelper.insertUser({
      'name': name,
      'email': email,
    });
  }
  
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    return await _dbHelper.getUsers();
  }
}
```

---

## 最佳实践

### 1. 代码组织

```dart
// 项目结构建议
lib/
├── main.dart                 // 应用入口
├── models/                   // 数据模型
│   ├── user.dart
│   └── product.dart
├── services/                 // 服务层
│   ├── api_service.dart
│   └── storage_service.dart
├── providers/                // 状态管理
│   └── user_provider.dart
├── screens/                  // 页面
│   ├── home_screen.dart
│   └── detail_screen.dart
├── widgets/                  // 可复用组件
│   ├── custom_button.dart
│   └── loading_widget.dart
└── utils/                    // 工具类
    ├── constants.dart
    └── helpers.dart
```

### 2. 错误处理

```dart
// 统一的错误处理
class AppException implements Exception {
  final String message;
  final String? code;
  
  AppException(this.message, [this.code]);
  
  @override
  String toString() => 'AppException: $message';
}

// 网络请求错误处理
Future<T> handleApiCall<T>(Future<T> Function() apiCall) async {
  try {
    return await apiCall();
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionTimeout) {
      throw AppException('连接超时，请检查网络');
    } else if (e.type == DioExceptionType.receiveTimeout) {
      throw AppException('请求超时，请重试');
    } else {
      throw AppException('网络错误: ${e.message}');
    }
  } catch (e) {
    throw AppException('未知错误: $e');
  }
}

// 在 Widget 中处理错误
class SafeWidget extends StatelessWidget {
  final Widget child;
  final Widget Function(String error)? errorBuilder;
  
  const SafeWidget({
    Key? key,
    required this.child,
    this.errorBuilder,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return ErrorWidget.builder = (FlutterErrorDetails details) {
      if (errorBuilder != null) {
        return errorBuilder!(details.exception.toString());
      }
      return Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text('出错了！'),
            Text(details.exception.toString()),
          ],
        ),
      );
    };
  }
}
```

### 3. 性能优化

```dart
// 使用 const 构造函数
class MyWidget extends StatelessWidget {
  const MyWidget({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Text('Hello'); // 使用 const
  }
}

// 使用 ListView.builder 而不是 ListView
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return ListTile(
      title: Text(items[index].title),
    );
  },
)

// 使用 RepaintBoundary 隔离重绘
RepaintBoundary(
  child: MyExpensiveWidget(),
)

// 使用 AutomaticKeepAliveClientMixin 保持状态
class _MyWidgetState extends State<MyWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用
    return MyWidget();
  }
}
```

### 4. 主题和样式

```dart
// 定义主题
class AppTheme {
  static ThemeData lightTheme = ThemeData(
    primarySwatch: Colors.blue,
    brightness: Brightness.light,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
  );
  
  static ThemeData darkTheme = ThemeData(
    primarySwatch: Colors.blue,
    brightness: Brightness.dark,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[900],
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

// 在 MaterialApp 中使用
MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: ThemeMode.system, // 跟随系统
)
```

### 5. 国际化

```dart
// 首先添加依赖到 pubspec.yaml
// flutter_localizations:
//   sdk: flutter
// intl: ^0.18.0

// 定义本地化字符串
class AppLocalizations {
  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'hello': 'Hello',
      'welcome': 'Welcome',
    },
    'zh': {
      'hello': '你好',
      'welcome': '欢迎',
    },
  };
  
  static String getString(String key, String languageCode) {
    return _localizedValues[languageCode]?[key] ?? key;
  }
}

// 在 MaterialApp 中配置
MaterialApp(
  localizationsDelegates: [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: [
    const Locale('en', ''),
    const Locale('zh', ''),
  ],
)
```

---

## 常用命令

```bash
# 创建新项目
flutter create my_app

# 运行项目
flutter run

# 构建 APK
flutter build apk

# 构建 iOS
flutter build ios

# 获取依赖
flutter pub get

# 升级依赖
flutter pub upgrade

# 清理项目
flutter clean

# 分析代码
flutter analyze

# 运行测试
flutter test

# 格式化代码
dart format .

# 检查设备
flutter devices
```

---

## 常用包推荐

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 状态管理
  provider: ^6.0.0
  flutter_bloc: ^8.0.0
  
  # 网络请求
  http: ^0.13.0
  dio: ^5.0.0
  
  # 本地存储
  shared_preferences: ^2.0.0
  sqflite: ^2.0.0
  
  # UI 组件
  cached_network_image: ^3.0.0
  flutter_svg: ^2.0.0
  
  # 工具
  intl: ^0.18.0
  url_launcher: ^6.0.0
  permission_handler: ^10.0.0
  
  # 图表
  fl_chart: ^0.60.0
  
  # 动画
  lottie: ^2.0.0
```

---

这份文档涵盖了 Flutter 开发的主要语法和概念。建议你：

1. **循序渐进**：先掌握 Dart 基础，再学习 Flutter 框架
2. **实践为主**：多写代码，多调试
3. **查阅官方文档**：Flutter 官方文档是最权威的参考
4. **参与社区**：关注 Flutter 社区，学习最佳实践

祝你 Flutter 开发愉快！🚀 