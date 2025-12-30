import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService().initialize();
  runApp(const MJXApp());
}

class MJXApp extends StatelessWidget {
  const MJXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => MarketProvider()),
      ],
      child: MaterialApp(
        title: 'MJX Crypto Exchange',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF00D9FF),
          scaffoldBackgroundColor: const Color(0xFF0A0E27),
          cardColor: const Color(0xFF1E2139),
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0A0E27),
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ==================== MODELS ====================
class UserModel {
  final String uid;
  final String email;
  final String name;
  final double balance;
  final DateTime createdAt;
  final Map<String, double> wallets;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.balance,
    required this.createdAt,
    required this.wallets,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      balance: (map['balance'] ?? 0).toDouble(),
      createdAt:
          DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      wallets: Map<String, double>.from(map['wallets'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'balance': balance,
      'createdAt': createdAt.toIso8601String(),
      'wallets': wallets,
    };
  }
}

class TransactionModel {
  final String id;
  final String userId;
  final String type;
  final String currency;
  final double amount;
  final double? price;
  final double fees;
  final DateTime timestamp;
  final String status;

  TransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.currency,
    required this.amount,
    this.price,
    required this.fees,
    required this.timestamp,
    required this.status,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map, String id) {
    return TransactionModel(
      id: id,
      userId: map['userId'] ?? '',
      type: map['type'] ?? '',
      currency: map['currency'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      price: map['price']?.toDouble(),
      fees: (map['fees'] ?? 0).toDouble(),
      timestamp:
          DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
      status: map['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'currency': currency,
      'amount': amount,
      'price': price,
      'fees': fees,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
    };
  }
}

class CurrencyModel {
  final String symbol;
  final String name;
  final double currentPrice;
  final double change24h;
  final List<double> sparklineData;
  final bool isFuture;
  final double? leverage;

  CurrencyModel({
    required this.symbol,
    required this.name,
    required this.currentPrice,
    required this.change24h,
    required this.sparklineData,
    this.isFuture = false,
    this.leverage,
  });
}

// ==================== SERVICES ====================
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  Future<String?> signUp(String email, String password, String name) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password, // Fixed: removed duplicate 'password:'
      );
      await _firestore.collection('users').doc(result.user!.uid).set({
        'email': email,
        'name': name,
        'balance': 10000.0,
        'createdAt': DateTime.now().toIso8601String(),
        'wallets': {
          'BTC': 0.0,
          'ETH': 0.0,
          'USDT': 0.0,
          'BNB': 0.0,
          'SOL': 0.0,
        },
      });
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  Stream<UserModel?> getUserStream() {
    if (currentUser == null) return Stream.value(null);
    return _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .snapshots()
        .map((doc) {
      if (doc.exists) return UserModel.fromMap(doc.data()!, doc.id);
      return null;
    });
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notifications.initialize(settings);
  }

  Future<void> showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'mjx_channel',
      'MJX Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(0, title, body, details);
  }
}

class WalletProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> deposit(double amount) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({
      'balance': FieldValue.increment(amount),
    });
    await _firestore.collection('transactions').add({
      'userId': uid,
      'type': 'deposit',
      'currency': 'USD',
      'amount': amount,
      'fees': 0.0,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
    });
    await NotificationService().showNotification('Deposit Successful',
        '\$${amount.toStringAsFixed(2)} added to your account');
    notifyListeners();
  }

  Future<void> withdraw(double amount) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({
      'balance': FieldValue.increment(-amount),
    });
    await _firestore.collection('transactions').add({
      'userId': uid,
      'type': 'withdraw',
      'currency': 'USD',
      'amount': amount,
      'fees': amount * 0.01,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
    });
    
    await NotificationService().showNotification(
        'Withdrawal Successful', '\$${amount.toStringAsFixed(2)} withdrawn');
    notifyListeners();
  }
  Future<bool> buyCrypto(String currency, double amount, double price,
      {bool isFuture = false, double leverage = 1.0}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final totalCost = amount * price * (isFuture ? leverage : 1.0);
    final doc = await _firestore.collection('users').doc(uid).get();
    final userData = doc.data()!;
    final currentBalance = (userData['balance'] ?? 0).toDouble();
    if (currentBalance < totalCost) return false;
    await _firestore.collection('users').doc(uid).update({
      'balance': FieldValue.increment(-totalCost),
      'wallets.$currency': FieldValue.increment(amount),
    });
    await _firestore.collection('transactions').add({
      'userId': uid,
      'type': isFuture ? 'buy_future' : 'buy',
      'currency': currency,
      'amount': amount,
      'price': price,
      'fees': totalCost * 0.001,
      'leverage': isFuture ? leverage : 1.0,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
    });
    await NotificationService().showNotification('Purchase Complete',
        'Bought $amount $currency ${isFuture ? 'Futures' : ''}');
    notifyListeners();
    return true;
  }

  Future<bool> sellCrypto(String currency, double amount, double price,
      {bool isFuture = false}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _firestore.collection('users').doc(uid).get();
    final userData = doc.data()!;
    final wallets = Map<String, double>.from(userData['wallets'] ?? {});
    if ((wallets[currency] ?? 0) < amount) return false;
    final totalValue = amount * price;
    await _firestore.collection('users').doc(uid).update({
      'balance': FieldValue.increment(totalValue),
      'wallets.$currency': FieldValue.increment(-amount),
    });
    await _firestore.collection('transactions').add({
      'userId': uid,
      'type': isFuture ? 'sell_future' : 'sell',
      'currency': currency,
      'amount': amount,
      'price': price,
      'fees': totalValue * 0.001,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
    });
    await NotificationService().showNotification(
        'Sale Complete', 'Sold $amount $currency ${isFuture ? 'Futures' : ''}');
    notifyListeners();
    return true;
  }

  Future<void> transfer(String toEmail, String currency, double amount) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final toUserQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: toEmail)
        .limit(1)
        .get();
    if (toUserQuery.docs.isEmpty) throw Exception('User not found');
    final toUserId = toUserQuery.docs.first.id;
    await _firestore.collection('users').doc(uid).update({
      'wallets.$currency': FieldValue.increment(-amount),
    });
    await _firestore.collection('users').doc(toUserId).update({
      'wallets.$currency': FieldValue.increment(amount),
    });
    await _firestore.collection('transactions').add({
      'userId': uid,
      'type': 'transfer_out',
      'currency': currency,
      'amount': amount,
      'fees': 0.0,
      'toUserId': toUserId,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
    });
    await _firestore.collection('transactions').add({
      'userId': toUserId,
      'type': 'transfer_in',
      'currency': currency,
      'amount': amount,
      'fees': 0.0,
      'fromUserId': uid,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
    });
    await NotificationService().showNotification(
        'Transfer Complete', 'Transferred $amount $currency to $toEmail');
    notifyListeners();
  }
}

class MarketProvider extends ChangeNotifier {
  List<CurrencyModel> spotCurrencies = [];
  List<CurrencyModel> futureCurrencies = [];
  bool isLoading = false;

  Future<void> fetchPrices() async {
    isLoading = true;
    notifyListeners();
    try {
      final response = await http.get(Uri.parse(
          'https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ethereum,tether,binancecoin,solana&order=market_cap_desc&sparkline=true'));
      if (response.statusCode == 200) {
        List data = json.decode(response.body);
        spotCurrencies = data.map((coin) {
          List<double> sparkline = [];
          if (coin['sparkline_in_7d'] != null &&
              coin['sparkline_in_7d']['price'] != null) {
            sparkline = List<double>.from(
                coin['sparkline_in_7d']['price'].map((e) => e.toDouble()));
          }
          return CurrencyModel(
            symbol: coin['symbol'].toString().toUpperCase(),
            name: coin['name'],
            currentPrice: coin['current_price'].toDouble(),
            change24h: coin['price_change_percentage_24h'].toDouble(),
            sparklineData: sparkline.isEmpty
                ? List.generate(20, (i) => coin['current_price'].toDouble())
                : sparkline,
          );
        }).toList();
        futureCurrencies = spotCurrencies
            .map((c) => CurrencyModel(
                  symbol: c.symbol,
                  name: '${c.name} Future',
                  currentPrice: c.currentPrice * 1.02,
                  change24h: c.change24h * 1.5,
                  sparklineData: c.sparklineData,
                  isFuture: true,
                  leverage: 10.0,
                ))
            .toList();
      }
    } catch (e) {
      debugPrint('Error: $e'); // Fixed: debugPrint instead of print
    }
    isLoading = false;
    notifyListeners();
  }
}

// ==================== SCREENS ====================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final authService = Provider.of<AuthService>(context, listen: false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => authService.isAuthenticated
              ? const MainScreen()
              : const LoginScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0E27), Color(0xFF1E2139)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF00D9FF).withValues(alpha: 0.2), // Fixed
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.currency_bitcoin,
                    size: 80, color: Color(0xFF00D9FF)),
              ),
              const SizedBox(height: 30),
              const Text(
                'MJX',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Crypto Exchange',
                style: TextStyle(
                    fontSize: 18, color: Colors.white70, letterSpacing: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final error = await authService.signIn(
        _emailController.text.trim(), _passwordController.text);
    setState(() => _isLoading = false);
    if (error == null && mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error ?? 'Login failed'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E27), Color(0xFF1E2139)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  const Icon(Icons.currency_bitcoin,
                      size: 80, color: Color(0xFF00D9FF)),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Login to MJX Exchange',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 50),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFF1E2139),
                    ),
                    validator: (v) => v!.isEmpty ? 'Enter email' : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFF1E2139),
                    ),
                    validator: (v) => v!.isEmpty ? 'Enter password' : null,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D9FF),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Login', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? "),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegisterScreen()),
                        ),
                        child: const Text('Sign Up',
                            style: TextStyle(color: Color(0xFF00D9FF))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Passwords do not match'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final error = await authService.signUp(
      _emailController.text.trim(),
      _passwordController.text,
      _nameController.text.trim(),
    );
    setState(() => _isLoading = false);
    if (error == null && mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error ?? 'Registration failed'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: const Color(0xFF0A0E27),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E27), Color(0xFF1E2139)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Join MJX',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Start trading crypto today',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFF1E2139),
                    ),
                    validator: (v) => v!.isEmpty ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFF1E2139),
                    ),
                    validator: (v) {
                      if (v!.isEmpty) return 'Enter email';
                      if (!v.contains('@')) return 'Enter valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFF1E2139),
                    ),
                    validator: (v) =>
                        v!.length < 6 ? 'Password must be 6+ characters' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFF1E2139),
                    ),
                    validator: (v) => v!.isEmpty ? 'Confirm password' : null,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Create Account',
                              style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== MAIN SCREEN ====================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _screens = [
    const HomeScreen(),
    const MarketScreen(),
    const WalletScreen(),
    const TransactionsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E2139),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3), // Fixed
                blurRadius: 10,
                offset: const Offset(0, -2)),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF1E2139),
          selectedItemColor: const Color(0xFF00D9FF),
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.candlestick_chart), label: 'Market'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
            BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long), label: 'History'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

// ==================== HOME SCREEN ====================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MJX Exchange',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: StreamBuilder<UserModel?>(
        stream: authService.getUserStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hello, ${user.name}!',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D9FF), Color(0xFF0088CC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Balance',
                          style:
                              TextStyle(fontSize: 14, color: Colors.white70)),
                      const SizedBox(height: 8),
                      Text(
                        '\$${user.balance.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showDepositDialog(context),
                              icon: const Icon(Icons.add,
                                  color: Color(0xFF00D9FF)),
                              label: const Text('Deposit',
                                  style: TextStyle(color: Color(0xFF00D9FF))),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _showWithdrawDialog(context, user.balance),
                              icon: const Icon(Icons.remove,
                                  color: Color(0xFF00D9FF)),
                              label: const Text('Withdraw',
                                  style: TextStyle(color: Color(0xFF00D9FF))),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const Text('My Crypto',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...user.wallets.entries.where((e) => e.value > 0).map((entry) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF00D9FF)
                            .withValues(alpha: 0.2), // Fixed
                        child: Text(entry.key,
                            style: const TextStyle(
                                color: Color(0xFF00D9FF),
                                fontWeight: FontWeight.bold)),
                      ),
                      title: Text(entry.key,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${entry.value.toStringAsFixed(6)} ${entry.key}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {},
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDepositDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deposit Funds'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount (USD)',
            prefixText: '\$ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Fixed: async
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                final walletProvider =
                    Provider.of<WalletProvider>(context, listen: false);
                await walletProvider.deposit(amount);
                if (!context.mounted) return; // Fixed: mounted check
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Deposit successful!')),
                );
              }
            },
            child: const Text('Deposit'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, double balance) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Funds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Available: \$${balance.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (USD)',
                prefixText: '\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Fixed: async
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0 && amount <= balance) {
                final walletProvider =
                    Provider.of<WalletProvider>(context, listen: false);
                await walletProvider.withdraw(amount);
                if (!context.mounted) return; // Fixed: mounted check
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Withdrawal successful!')),
                );
              } else {
                if (!context.mounted) return; // Fixed
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Invalid amount'),
                      backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }
}

// ==================== MARKET SCREEN ====================
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MarketProvider>(context, listen: false).fetchPrices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = Provider.of<MarketProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Market', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => marketProvider.fetchPrices(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00D9FF),
          labelColor: const Color(0xFF00D9FF),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Spot'),
            Tab(text: 'Futures'),
          ],
        ),
      ),
      body: marketProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCurrencyList(marketProvider.spotCurrencies, false),
                _buildCurrencyList(marketProvider.futureCurrencies, true),
              ],
            ),
    );
  }

  Widget _buildCurrencyList(List<CurrencyModel> currencies, bool isFuture) {
    if (currencies.isEmpty) {
      return const Center(child: Text('No data available'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        await Provider.of<MarketProvider>(context, listen: false).fetchPrices();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: currencies.length,
        itemBuilder: (context, index) {
          final currency = currencies[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TradingScreen(currency: currency),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF00D9FF)
                          .withValues(alpha: 0.2), // Fixed
                      child: Text(
                        currency.symbol.substring(0, 1),
                        style: const TextStyle(
                            color: Color(0xFF00D9FF),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currency.symbol,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            currency.name,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      height: 40,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: currency.sparklineData
                                  .asMap()
                                  .entries
                                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                                  .toList(),
                              isCurved: true,
                              color: currency.change24h >= 0
                                  ? Colors.green
                                  : Colors.red,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${currency.currentPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: currency.change24h >= 0
                                ? Colors.green.withValues(alpha: 0.2) // Fixed
                                : Colors.red.withValues(alpha: 0.2), // Fixed
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${currency.change24h >= 0 ? '+' : ''}${currency.change24h.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: currency.change24h >= 0
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
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
        },
      ),
    );
  }
}

// ==================== TRADING SCREEN ====================
class TradingScreen extends StatefulWidget {
  final CurrencyModel currency;
  const TradingScreen({super.key, required this.currency});

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> {
  final _amountController = TextEditingController();
  bool _isBuying = true;
  double _leverage = 1.0;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.currency.symbol} Trading'),
      ),
      body: StreamBuilder<UserModel?>(
        stream: authService.getUserStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data!;
          final amount = double.tryParse(_amountController.text) ?? 0;
          final total = amount *
              widget.currency.currentPrice *
              (widget.currency.isFuture ? _leverage : 1.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          widget.currency.name,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '\$${widget.currency.currentPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 32, color: Color(0xFF00D9FF)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.currency.change24h >= 0
                                ? Colors.green.withValues(alpha: 0.2) // Fixed
                                : Colors.red.withValues(alpha: 0.2), // Fixed
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${widget.currency.change24h >= 0 ? '+' : ''}${widget.currency.change24h.toStringAsFixed(2)}% (24h)',
                            style: TextStyle(
                              color: widget.currency.change24h >= 0
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color:
                                    Colors.grey.withValues(alpha: 0.2), // Fixed
                                strokeWidth: 1,
                              );
                            },
                          ),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: widget.currency.sparklineData
                                  .asMap()
                                  .entries
                                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                                  .toList(),
                              isCurved: true,
                              color: const Color(0xFF00D9FF),
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: const Color(0xFF00D9FF)
                                    .withValues(alpha: 0.1), // Fixed
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => setState(() => _isBuying = true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isBuying
                              ? Colors.green
                              : Colors.grey.withValues(alpha: 0.3), // Fixed
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Buy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => setState(() => _isBuying = false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !_isBuying
                              ? Colors.red
                              : Colors.grey.withValues(alpha: 0.3), // Fixed
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Sell'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (widget.currency.isFuture) ...[
                  const Text('Leverage',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [1.0, 2.0, 5.0, 10.0].map((lev) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: OutlinedButton(
                            onPressed: () => setState(() => _leverage = lev),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _leverage == lev
                                  ? const Color(0xFF00D9FF)
                                      .withValues(alpha: 0.2) // Fixed
                                  : null,
                              side: BorderSide(
                                color: _leverage == lev
                                    ? const Color(0xFF00D9FF)
                                    : Colors.grey,
                              ),
                            ),
                            child: Text('${lev.toInt()}x'),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount (${widget.currency.symbol})',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFF1E2139),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Available Balance:'),
                            Text('\$${user.balance.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (!_isBuying) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Available ${widget.currency.symbol}:'),
                              Text(
                                '${(user.wallets[widget.currency.symbol] ?? 0).toStringAsFixed(6)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total:',
                                style: TextStyle(fontSize: 16)),
                            Text(
                              '\$${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00D9FF)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () => _executeTrade(context, user),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isBuying ? Colors.green : Colors.red,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _isBuying
                          ? 'Buy ${widget.currency.symbol}'
                          : 'Sell ${widget.currency.symbol}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeTrade(BuildContext context, UserModel user) async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Enter valid amount'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    bool success;
    if (_isBuying) {
      success = await walletProvider.buyCrypto(
        widget.currency.symbol,
        amount,
        widget.currency.currentPrice,
        isFuture: widget.currency.isFuture,
        leverage: _leverage,
      );
    } else {
      success = await walletProvider.sellCrypto(
        widget.currency.symbol,
        amount,
        widget.currency.currentPrice,
        isFuture: widget.currency.isFuture,
      );
    }
    if (success && mounted) {
      _amountController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${_isBuying ? 'Purchase' : 'Sale'} successful!')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Insufficient balance'), backgroundColor: Colors.red),
      );
    }
  }
}

// ==================== WALLET SCREEN ====================
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<UserModel?>(
        stream: authService.getUserStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('Total Balance',
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(
                          '\$${user.balance.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00D9FF)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showDepositDialog(context),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Deposit'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _showWithdrawDialog(context, user.balance),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Withdraw'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _showTransferDialog(context),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Transfer'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 30),
                const Text('My Assets',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...user.wallets.entries.map((entry) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF00D9FF)
                            .withValues(alpha: 0.2), // Fixed
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                              color: Color(0xFF00D9FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ),
                      title: Text(entry.key,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${entry.value.toStringAsFixed(6)} ${entry.key}'),
                      trailing: Text(
                        entry.value > 0
                            ? '\$${(entry.value * 1000).toStringAsFixed(2)}'
                            : '\$0.00',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00D9FF)),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDepositDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deposit Funds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter amount to deposit'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (USD)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Fixed: async
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                final walletProvider =
                    Provider.of<WalletProvider>(context, listen: false);
                await walletProvider.deposit(amount);
                if (!context.mounted) return; // Fixed
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Deposit successful!')),
                );
              }
            },
            child: const Text('Deposit'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, double balance) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Funds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Available: \$${balance.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (USD)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('1% withdrawal fee applies',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Fixed: async
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0 && amount <= balance) {
                final walletProvider =
                    Provider.of<WalletProvider>(context, listen: false);
                await walletProvider.withdraw(amount);
                if (!context.mounted) return; // Fixed
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Withdrawal successful!')),
                );
              } else {
                if (!context.mounted) return; // Fixed
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Invalid amount'),
                      backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }

  void _showTransferDialog(BuildContext context) {
    final emailController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCurrency = 'BTC';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Transfer Crypto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Recipient Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedCurrency, // Fixed: value instead of initialValue
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                items: ['BTC', 'ETH', 'USDT', 'BNB', 'SOL'].map((currency) {
                  return DropdownMenuItem(
                      value: currency, child: Text(currency));
                }).toList(),
                onChanged: (value) => setDialogState(
                    () => selectedCurrency = value!), // Fixed: setDialogState
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  border: const OutlineInputBorder(),
                  suffixText: selectedCurrency,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Fixed: async
                final amount = double.tryParse(amountController.text);
                if (amount != null &&
                    amount > 0 &&
                    emailController.text.isNotEmpty) {
                  try {
                    final walletProvider =
                        Provider.of<WalletProvider>(context, listen: false);
                    await walletProvider.transfer(
                      emailController.text.trim(),
                      selectedCurrency,
                      amount,
                    );
                    if (!context.mounted) return; // Fixed
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transfer successful!')),
                    );
                  } catch (e) {
                    if (!context.mounted) return; // Fixed
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== TRANSACTIONS SCREEN ====================
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view transactions')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('userId', isEqualTo: uid)
            .orderBy('timestamp', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long,
                      size: 80,
                      color: Colors.grey.withValues(alpha: 0.5)), // Fixed
                  const SizedBox(height: 16),
                  const Text('No transactions yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }
          final transactions = snapshot.data!.docs
              .map((doc) => TransactionModel.fromMap(
                  doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final transaction = transactions[index];
              return _buildTransactionCard(transaction);
            },
          );
        },
      ),
    );
  }

  Widget _buildTransactionCard(TransactionModel transaction) {
    IconData icon;
    Color iconColor;
    String title;
    switch (transaction.type) {
      case 'deposit':
        icon = Icons.add_circle;
        iconColor = Colors.green;
        title = 'Deposit';
        break;
      case 'withdraw':
        icon = Icons.remove_circle;
        iconColor = Colors.red;
        title = 'Withdrawal';
        break;
      case 'buy':
      case 'buy_future':
        icon = Icons.shopping_cart;
        iconColor = Colors.blue;
        title = transaction.type == 'buy_future' ? 'Buy Future' : 'Buy';
        break;
      case 'sell':
      case 'sell_future':
        icon = Icons.sell;
        iconColor = Colors.orange;
        title = transaction.type == 'sell_future' ? 'Sell Future' : 'Sell';
        break;
      case 'transfer_out':
        icon = Icons.arrow_upward;
        iconColor = Colors.purple;
        title = 'Transfer Out';
        break;
      case 'transfer_in':
        icon = Icons.arrow_downward;
        iconColor = Colors.teal;
        title = 'Transfer In';
        break;
      default:
        icon = Icons.receipt;
        iconColor = Colors.grey;
        title = 'Transaction';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.2), // Fixed
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${transaction.amount.toStringAsFixed(6)} ${transaction.currency}'),
            Text(
              DateFormat('MMM dd, yyyy - hh:mm a')
                  .format(transaction.timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (transaction.price != null)
              Text(
                '\$${(transaction.amount * transaction.price!).toStringAsFixed(2)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: transaction.status == 'completed'
                    ? Colors.green.withValues(alpha: 0.2) // Fixed
                    : Colors.orange.withValues(alpha: 0.2), // Fixed
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                transaction.status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: transaction.status == 'completed'
                      ? Colors.green
                      : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Transactions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All Transactions'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('Deposits'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('Withdrawals'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('Trades'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('Transfers'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== PROFILE SCREEN ====================
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<UserModel?>(
        stream: authService.getUserStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor:
                      const Color(0xFF00D9FF).withValues(alpha: 0.2), // Fixed
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00D9FF)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                Text(user.email,
                    style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  'Member since ${DateFormat('MMMM yyyy').format(user.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 30),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Edit Profile'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _showEditProfileDialog(context, user),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.security),
                        title: const Text('Security'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {},
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Notifications'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {},
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: const Text('Help & Support'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {},
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('About'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _showAboutDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _logout(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.withValues(alpha: 0.5)), // Fixed
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, UserModel user) {
    final nameController = TextEditingController(text: user.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Full Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .update({'name': nameController.text.trim()});
                if (!context.mounted) return; // Fixed
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated!')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About MJX Exchange'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MJX Crypto Exchange',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SizedBox(height: 8),
            Text('Version: 1.0.0'),
            SizedBox(height: 16),
            Text(
                'A professional crypto trading platform with spot and futures trading capabilities.'),
            SizedBox(height: 16),
            Text('© 2024 MJX Exchange. All rights reserved.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Provider.of<AuthService>(context, listen: false).signOut();
              if (!context.mounted) return; // Fixed
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ==================== FIREBASE SETUP INSTRUCTIONS (Same as original) ====================
/*
FIREBASE SETUP:
1. Create Firebase Project:
   - Go to https://console.firebase.google.com
   - Click "Add project"
   - Enter project name: "mjx-crypto-exchange"
   - Enable Google Analytics (optional)
2. Add Android App:
   - Click Android icon
   - Package name: com.example.mjx_crypto_exchange
   - Download google-services.json
   - Place in: android/app/google-services.json
3. Add iOS App:
   - Click iOS icon
   - Bundle ID: com.example.mjxCryptoExchange
   - Download GoogleService-Info.plist
   - Place in: ios/Runner/GoogleService-Info.plist
4. Enable Authentication:
   - Go to Authentication > Sign-in method
   - Enable Email/Password
5. Setup Firestore:
   - Go to Firestore Database
   - Create database in production mode
   - Add these security rules:
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    match /transactions/{transactionId} {
      allow read: if request.auth != null && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null;
    }
  }
}
6. Enable Cloud Messaging (optional):
   - Go to Cloud Messaging
   - Enable the API
7. Android Configuration:
   - In android/build.gradle, add:
     classpath 'com.google.gms:google-services:4.4.2'  // Updated for latest
   - In android/app/build.gradle, add:
     apply plugin: 'com.google.gms.google-services'
   - Set minSdkVersion to 21
8. iOS Configuration:
   - Run: cd ios && pod install
   - Update Info.plist with notification permissions
9. Run the app:
   flutter pub get
   flutter run
TESTING:
- Create test user account
- Test deposit/withdraw
- Test buying/selling crypto
- Test transfers between users
- Check transaction history
- Verify notifications work
*/
