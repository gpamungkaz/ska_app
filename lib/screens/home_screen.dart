
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ska_app/services/auth_storage.dart';
import 'package:ska_app/services/api_config.dart';
import 'login_screen.dart';

enum UserRole { marketing, owner }

enum DashboardMenu { visit, spk, customer, unitMovement }

extension UserRoleLabel on UserRole {
  String get displayName => switch (this) {
    UserRole.marketing => 'Marketing',
    UserRole.owner => 'Owner',
  };
}

extension DashboardMenuMetadata on DashboardMenu {
  IconData get icon => switch (this) {
    DashboardMenu.visit => Icons.visibility_outlined,
    DashboardMenu.customer => Icons.groups_outlined,
    DashboardMenu.spk => Icons.assignment_outlined,
    DashboardMenu.unitMovement => Icons.local_shipping_outlined,
  };

  Color get accentColor => switch (this) {
    DashboardMenu.visit => Colors.blue,
    DashboardMenu.customer => Colors.deepPurple,
    DashboardMenu.spk => Colors.orange,
    DashboardMenu.unitMovement => Colors.teal,
  };

  String get title => switch (this) {
    DashboardMenu.visit => 'Visit',
    DashboardMenu.customer => 'Customer',
    DashboardMenu.spk => 'SPK',
    DashboardMenu.unitMovement => 'Keluar Masuk Unit',
  };

  String get subtitle => switch (this) {
    DashboardMenu.visit => 'Pantau aktivitas kunjungan',
    DashboardMenu.customer => 'Kelola relasi pelanggan',
    DashboardMenu.spk => 'Pantau proses SPK',
    DashboardMenu.unitMovement => 'Lihat pergerakan unit',
  };
}

Future<void> _logout(BuildContext context) async {
	final navigator = Navigator.of(context);
	await AuthStorage.clearSession();
	navigator.pushAndRemoveUntil(
		MaterialPageRoute(builder: (_) => const LoginScreen()),
		(route) => false,
	);
}

class HomeScreen extends StatelessWidget {
	const HomeScreen({
		super.key,
		required this.role,
		required this.authToken,
		this.userName,
	});

	final UserRole role;
	final String authToken;
	final String? userName;

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case UserRole.marketing:
				return MarketingHomeScreen(
					authToken: authToken,
					userName: userName,
				);
      case UserRole.owner:
				return OwnerHomeScreen(
					userName: userName,
					authToken: authToken,
				);
    }
  }
}

class MarketingHomeScreen extends StatefulWidget {
	const MarketingHomeScreen({
		super.key,
		required this.authToken,
		this.userName,
	});

	final String authToken;
	final String? userName;

  @override
  State<MarketingHomeScreen> createState() => _MarketingHomeScreenState();
}

class _MarketingHomeScreenState extends State<MarketingHomeScreen> {
	static String get _visitsEndpoint => ApiConfig.visitsEndpoint;
	static String get _dealersEndpoint => ApiConfig.dealersEndpoint;
	static String get _purchaseOrdersEndpoint => ApiConfig.purchaseOrdersEndpoint;
	static String get _bodyTypesEndpoint => ApiConfig.bodyTypesEndpoint;

  DashboardMenu _selectedMenu = DashboardMenu.customer;
  final List<DashboardMenu> _marketingMenus = [
    DashboardMenu.customer,
    DashboardMenu.spk,
    DashboardMenu.unitMovement,
  ];
  bool _isVisitLoading = false;
	bool _isSubmittingVisit = false;
  String? _visitErrorMessage;
  List<VisitData> _visits = const [];
  
  bool _isSpkLoading = false;
  bool _isSubmittingSpk = false;
  String? _spkErrorMessage;
  List<PurchaseOrderData> _purchaseOrders = const [];

  bool _isUnitMovementLoading = false;
  String? _unitMovementErrorMessage;
  List<PurchaseOrderData> _unitMovementOrders = const [];
  List<PurchaseOrderData> _filteredUnitMovementOrders = const [];
  final TextEditingController _unitMovementSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchVisits();
    _fetchPurchaseOrders();
    _fetchUnitMovementOrders();
    _unitMovementSearchController.addListener(_applyUnitMovementFilter);
  }

  @override
  void dispose() {
    _unitMovementSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchVisits() async {
    if (!mounted) return;

    setState(() {
      _isVisitLoading = true;
      _visitErrorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(_visitsEndpoint),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
      );

		if (response.statusCode == 401) {
			await _handleSessionExpired();
			return;
		}

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          decoded['success'] == true) {
        final rawData = decoded['data'];
				final visits = rawData is List
						? rawData
								.whereType<Map<String, dynamic>>()
								.map(
									(visitJson) => VisitData.fromJson(
										visitJson,
										mediaBaseUrl: ApiConfig.baseUrl,
									),
								)
								.toList()
						: const <VisitData>[];

        if (!mounted) return;
        setState(() {
          _visits = visits;
        });
      } else {
        final message =
            decoded['message']?.toString() ?? 'Gagal memuat data kunjungan.';
        throw _VisitException(message);
      }
    } on _VisitException catch (error) {
      if (!mounted) return;
      setState(() {
        _visitErrorMessage = error.message;
        _visits = const [];
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _visitErrorMessage = 'Format data visit tidak valid.';
        _visits = const [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _visitErrorMessage = 'Terjadi kesalahan: ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVisitLoading = false;
        });
      }
    }
  }

	Future<void> _openVisitCreationSheet() async {
			if (_isVisitLoading || _isSubmittingVisit) return;

		await showModalBottomSheet<void>(
			context: context,
			useSafeArea: true,
			showDragHandle: true,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
			),
			builder: (context) => _VisitCreationOptions(
				onSelectExisting: () {
					Navigator.of(context).pop();
					_startExistingDealerFlow();
				},
				onSelectNew: () {
					Navigator.of(context).pop();
					_startNewDealerFlow();
				},
			),
		);
	}

		Future<void> _startExistingDealerFlow() async {
			final selectedDealer = await showModalBottomSheet<DealerData>(
				context: context,
				useSafeArea: true,
				isScrollControlled: true,
				showDragHandle: true,
				shape: const RoundedRectangleBorder(
					borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
				),
				builder: (context) => _DealerSelectionSheet(
					authToken: widget.authToken,
					endpoint: _dealersEndpoint,
				),
			);

			if (!mounted || selectedDealer == null) return;

			_openExistingDealerVisitForm(selectedDealer);
		}

			Future<void> _startNewDealerFlow() async {
				final payload = await showModalBottomSheet<VisitSubmissionPayload>(
					context: context,
					useSafeArea: true,
					isScrollControlled: true,
					showDragHandle: true,
					shape: const RoundedRectangleBorder(
						borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
					),
					builder: (context) => _NewDealerVisitSheet(
						onCompleted: (result) => Navigator.of(context).pop(result),
					),
				);

				if (!mounted || payload == null) return;

				_submitVisit(payload);
			}

				Future<void> _openExistingDealerVisitForm(DealerData dealer) async {
					final payload = await showModalBottomSheet<VisitSubmissionPayload>(
						context: context,
						useSafeArea: true,
						isScrollControlled: true,
						showDragHandle: true,
						shape: const RoundedRectangleBorder(
							borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
						),
						builder: (context) => _ExistingDealerVisitSheet(
							dealer: dealer,
							onCompleted: (result) => Navigator.of(context).pop(result),
						),
					);

					if (!mounted || payload == null) return;

					_submitVisit(payload);
				}

			Future<void> _submitVisit(VisitSubmissionPayload payload) async {
					if (_isSubmittingVisit) return;

					setState(() {
						_isSubmittingVisit = true;
					});

					try {
						final request = http.MultipartRequest(
							'POST',
							Uri.parse(_visitsEndpoint),
						)
							..headers.addAll({
								'Accept': 'application/json',
								'Authorization': 'Bearer ${widget.authToken}',
							});

						final fields = <String, String>{
							'visit_type':
									payload.type == VisitDealerType.existing ? 'existing' : 'new',
							'latitude': payload.latitude.toString(),
							'longitude': payload.longitude.toString(),
						};

						if (payload.type == VisitDealerType.existing) {
							final dealer = payload.dealer;
							if (dealer == null) {
								throw const _VisitException('Dealer yang dipilih tidak valid.');
							}
							fields['dealer_id'] = dealer.id.toString();
						} else {
							fields['dealer_name'] = payload.customDealerName ?? '';
							fields['dealer_phone'] = payload.customDealerPhone ?? '';
							fields['dealer_address'] = payload.customDealerAddress ?? '';
							fields['customer_name'] = payload.customerName ?? '';
							fields['customer_address'] = payload.customerAddress ?? '';
							fields['customer_phone'] = payload.customerPhone ?? '';
						}

						request.fields.addAll(fields);

						final selfieBytes = await payload.selfie.readAsBytes();
						request.files.add(
							http.MultipartFile.fromBytes(
								'selfie',
								selfieBytes,
								filename: 'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg',
								contentType: MediaType('image', 'jpeg'),
							),
						);

						final streamed = await request.send();
						final response = await http.Response.fromStream(streamed);

						if (response.statusCode == 401) {
							await _handleSessionExpired();
							return;
						}
						final decoded = jsonDecode(response.body) as Map<String, dynamic>;

						if (response.statusCode >= 200 &&
								response.statusCode < 300 &&
								decoded['success'] == true) {
							if (!mounted) return;
							ScaffoldMessenger.of(context).showSnackBar(
								const SnackBar(content: Text('Visit berhasil disimpan.')),
							);
							await _fetchVisits();
						} else {
							final message =
									decoded['message']?.toString() ?? 'Gagal menyimpan visit baru.';
							throw _VisitException(message);
						}
					} on _VisitException catch (error) {
						if (!mounted) return;
						ScaffoldMessenger.of(context).showSnackBar(
							SnackBar(content: Text(error.message)),
						);
					} catch (error) {
						if (!mounted) return;
						ScaffoldMessenger.of(context).showSnackBar(
							SnackBar(content: Text('Terjadi kesalahan: $error')),
						);
					} finally {
						if (mounted) {
							setState(() {
								_isSubmittingVisit = false;
							});
						}
					}
			}

			Future<void> _handleSessionExpired([String? message]) async {
				if (!mounted) return;
				final messenger = ScaffoldMessenger.of(context);
				messenger
					..hideCurrentSnackBar()
					..showSnackBar(
						SnackBar(
							content: Text(
								message ?? 'Sesi login berakhir. Silakan login kembali.',
							),
						),
					);
				await _logout(context);
			}

	Future<void> _fetchUnitMovementOrders() async {
		if (!mounted) return;

		setState(() {
			_isUnitMovementLoading = true;
			_unitMovementErrorMessage = null;
		});

		try {
			final response = await http.get(
				Uri.parse('${ApiConfig.baseUrl}/api/v1/purchase-orders?status[]=approved&status[]=in_progress'),
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				setState(() {
					_isUnitMovementLoading = false;
				});
				await _handleSessionExpired();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				final raw = decoded['data'];
				final orders = raw is List
						? raw
								.map((item) => item is Map<String, dynamic>
										? PurchaseOrderData.fromJson(item)
										: null)
								.whereType<PurchaseOrderData>()
								.toList()
						: <PurchaseOrderData>[];
				setState(() {
					_unitMovementOrders = orders;
					_filteredUnitMovementOrders = orders;
					_isUnitMovementLoading = false;
				});
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal memuat data SPK.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			if (!mounted) return;
			setState(() {
				_unitMovementErrorMessage = error.message;
				_unitMovementOrders = const [];
				_filteredUnitMovementOrders = const [];
				_isUnitMovementLoading = false;
			});
		} on FormatException {
			if (!mounted) return;
			setState(() {
				_unitMovementErrorMessage = 'Format data SPK tidak valid.';
				_unitMovementOrders = const [];
				_filteredUnitMovementOrders = const [];
				_isUnitMovementLoading = false;
			});
		} catch (error) {
			if (!mounted) return;
			setState(() {
				_unitMovementErrorMessage = 'Terjadi kesalahan: ${error.toString()}';
				_isUnitMovementLoading = false;
			});
		}
	}

	void _applyUnitMovementFilter() {
		final query = _unitMovementSearchController.text.trim().toLowerCase();
		if (query.isEmpty) {
			setState(() {
				_filteredUnitMovementOrders = _unitMovementOrders;
			});
			return;
		}

		setState(() {
			_filteredUnitMovementOrders = _unitMovementOrders
					.where(
						(order) =>
								order.id.toString().contains(query) ||
								order.spkNumber.toLowerCase().contains(query) ||
								order.customerName.toLowerCase().contains(query) ||
								order.dealerName.toLowerCase().contains(query) ||
								order.merk.toLowerCase().contains(query) ||
								order.model.toLowerCase().contains(query) ||
								order.chassisNumber.toLowerCase().contains(query),
					)
					.toList();
		});
	}

	Future<void> _openSpkCreationSheet() async {
		if (_isSpkLoading || _isSubmittingSpk) return;

		await showModalBottomSheet<void>(
			context: context,
			useSafeArea: true,
			isScrollControlled: true,
			showDragHandle: true,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
			),
			builder: (context) => _AddPurchaseOrderSheet(
				authToken: widget.authToken,
				dealersEndpoint: _dealersEndpoint,
				bodyTypesEndpoint: _bodyTypesEndpoint,
				onCompleted: (payload) {
					Navigator.of(context).pop();
					_submitPurchaseOrder(payload);
				},
			),
		);
	}

	Future<void> _fetchPurchaseOrders() async {
		if (!mounted) return;

		setState(() {
			_isSpkLoading = true;
			_spkErrorMessage = null;
		});

		try {
			final response = await http.get(
				Uri.parse(_purchaseOrdersEndpoint),
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				setState(() {
					_isSpkLoading = false;
				});
				await _handleSessionExpired();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				final raw = decoded['data'];
				final orders = raw is List
						? raw
								.map((item) => item is Map<String, dynamic>
										? PurchaseOrderData.fromJson(item)
										: null)
								.whereType<PurchaseOrderData>()
								.toList()
						: <PurchaseOrderData>[];
				setState(() {
					_purchaseOrders = orders;
					_isSpkLoading = false;
				});
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal memuat data SPK.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			if (!mounted) return;
			setState(() {
				_spkErrorMessage = error.message;
				_purchaseOrders = const [];
				_isSpkLoading = false;
			});
		} on FormatException {
			if (!mounted) return;
			setState(() {
				_spkErrorMessage = 'Format data SPK tidak valid.';
				_purchaseOrders = const [];
				_isSpkLoading = false;
			});
		} catch (error) {
			if (!mounted) return;
			setState(() {
				_spkErrorMessage = 'Terjadi kesalahan: ${error.toString()}';
				_isSpkLoading = false;
			});
		}
	}

	Future<void> _submitPurchaseOrder(PurchaseOrderPayload payload) async {
		if (!mounted) return;

		setState(() {
			_isSubmittingSpk = true;
		});

		try {
			final body = jsonEncode({
				'dealer_id': payload.dealerId,
				'customer_name': payload.customerName,
				'customer_phone': payload.customerPhone,
				'customer_address': payload.customerAddress,
				'merk': payload.merk,
				'chassis_number': payload.chassisNumber,
				'model': payload.model,
				'body_type_id': payload.bodyTypeId,
				'outer_length': payload.outerLength,
				'outer_height': payload.outerHeight,
				'outer_width': payload.outerWidth,
				'optional': payload.optional,
				'unit_price': payload.unitPrice,
				'quantity': payload.quantity,
			});

			final response = await http.post(
				Uri.parse(_purchaseOrdersEndpoint),
				headers: {
					'Accept': 'application/json',
					'Content-Type': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
				body: body,
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				setState(() {
					_isSubmittingSpk = false;
				});
				await _handleSessionExpired();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				if (!mounted) return;
				ScaffoldMessenger.of(context).showSnackBar(
					const SnackBar(content: Text('SPK berhasil disimpan.')),
				);
				await _fetchPurchaseOrders();
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal menyimpan SPK baru.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text(error.message)),
			);
		} catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Terjadi kesalahan: $error')),
			);
		} finally {
			if (mounted) {
				setState(() {
					_isSubmittingSpk = false;
				});
			}
		}
	}

  void _handleMenuTap(DashboardMenu menu) {
    if (_selectedMenu == menu) return;
    setState(() {
      _selectedMenu = menu;
    });
  }

  Color _menuAccent(DashboardMenu menu) {
    if (menu == DashboardMenu.customer) {
      return Colors.deepPurple;
    }
    return menu.accentColor;
  }

  IconData _menuIcon(DashboardMenu menu) {
    if (menu == DashboardMenu.customer) {
      return Icons.place_outlined;
    }
    return menu.icon;
  }

  String _menuTitle(DashboardMenu menu) {
    if (menu == DashboardMenu.customer) {
      return 'Visit';
    }
    return menu.title;
  }

  String _menuSubtitle(DashboardMenu menu) {
    if (menu == DashboardMenu.customer) {
      return 'Kunjungan lapangan';
    }
    return menu.subtitle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Marketing Center',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.notifications_none),
          //   onPressed: () {
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       const SnackBar(content: Text('Notifikasi (dummy).')),
          //     );
          //   },
          // ),
					IconButton(
						icon: const Icon(Icons.logout_outlined),
						tooltip: 'Logout',
						onPressed: () => _logout(context),
					),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
			Text(
				'Selamat datang, ${widget.userName ?? 'Pengguna'}! 👋',
				style: const TextStyle(fontSize: 16, color: Colors.black54),
			),
            const SizedBox(height: 16),
						SizedBox(
							height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _marketingMenus.length,
							separatorBuilder: (context, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final menu = _marketingMenus[index];
                  final isSelected = _selectedMenu == menu;
                  final accent = _menuAccent(menu);

                  return GestureDetector(
                    onTap: () => _handleMenuTap(menu),
							child: AnimatedContainer(
								duration: const Duration(milliseconds: 200),
								width: 164,
								padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
									color: isSelected ? accent : Colors.white,
									borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
											color: Colors.black.withValues(alpha: 0.06),
											blurRadius: 10,
											offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
											radius: 22,
											backgroundColor: isSelected
												? Colors.white
												: accent.withValues(alpha: 0.18),
                            child: Icon(
												_menuIcon(menu),
												color: isSelected ? accent : accent,
												size: 22,
                            ),
                          ),
										const SizedBox(height: 12),
										Text(
                            _menuTitle(menu),
											style: TextStyle(
												fontSize: 15,
												fontWeight: FontWeight.w700,
												color: isSelected ? Colors.white : Colors.black87,
											),
                          ),
										const SizedBox(height: 4),
                          Text(
                            _menuSubtitle(menu),
											style: TextStyle(
												fontSize: 12,
												color: isSelected
													? Colors.white.withValues(alpha: 0.92)
													: Colors.black54,
											),
														maxLines: 2,
														overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.arrow_forward
                                    : Icons.visibility_outlined,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black45,
													size: 16,
                              ),
												const SizedBox(width: 4),
                              Text(
													isSelected ? 'Sedang dibuka' : 'Tap untuk buka',
                                style: TextStyle(
														color: isSelected
															? Colors.white
															: Colors.black54,
														fontSize: 11.5,
														fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildSelectedContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedContent() {
    switch (_selectedMenu) {
      case DashboardMenu.visit:
        // Should not happen for marketing
        return _buildVisitContent();
      case DashboardMenu.customer:
        return _buildVisitContent();
      case DashboardMenu.spk:
        return _buildSpkContent();
      case DashboardMenu.unitMovement:
        return _buildUnitMovementContent();
    }
  }

	Widget _buildVisitContent() {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				Row(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						const Expanded(
							child: Text(
								'Daftar Visit',
								style: TextStyle(
									fontSize: 20,
									fontWeight: FontWeight.bold,
								),
							),
						),
						Wrap(
							spacing: 8,
							runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _isVisitLoading ? null : _fetchVisits,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepPurple,
                    side: const BorderSide(color: Colors.deepPurple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.refresh_outlined),
                ),
                FilledButton(
                  onPressed: _isVisitLoading ? null : _openVisitCreationSheet,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.add_location_alt_outlined),
                ),
							],
						),
					],
				),
        const SizedBox(height: 16),
        Expanded(
          child: _isVisitLoading
              ? const Center(child: CircularProgressIndicator())
              : _visitErrorMessage != null
              ? _VisitErrorState(
                  message: _visitErrorMessage!,
                  onRetry: _fetchVisits,
                )
              : RefreshIndicator(
                  onRefresh: _fetchVisits,
                  child: _visits.isEmpty
                      ? const _VisitEmptyState()
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _visits.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final visit = _visits[index];
                            return _VisitCard(visit: visit, authToken: widget.authToken);
                          },
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildSpkContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Daftar SPK',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                if (_isSpkLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  OutlinedButton(
                  onPressed: _isSpkLoading ? null : _fetchPurchaseOrders,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.refresh_outlined),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSubmittingSpk ? null : _openSpkCreationSheet,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.add_task_outlined),
                ),
              ],
            ),
          ],
        ),
        if (_isSubmittingSpk) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Menyimpan SPK...',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sedang mengunggah data SPK ke server.',
                        style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: _isSpkLoading
              ? const Center(child: CircularProgressIndicator())
              : _spkErrorMessage != null
              ? _VisitErrorState(
                  message: _spkErrorMessage!,
                  onRetry: _fetchPurchaseOrders,
                )
              : RefreshIndicator(
                  onRefresh: _fetchPurchaseOrders,
                  child: _purchaseOrders.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 48),
                          children: const [
                            Icon(Icons.assignment_outlined, size: 72, color: Colors.black26),
                            SizedBox(height: 16),
                            Text(
                              'Belum ada data SPK tersedia.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, color: Colors.black54),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _purchaseOrders.length,
                          separatorBuilder: (context, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final order = _purchaseOrders[index];
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _SpkDetailSheet.show(context, order),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade200),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              order.spkNumber,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (order.status != null)
                                            _buildTag(
                                              order.status!,
                                              backgroundColor: Colors.orange.withValues(alpha: 0.12),
                                              foregroundColor: Colors.orange.shade700,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        order.customerName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Marketing: ${order.userName}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      _buildMetaRow(
                                        icon: Icons.store_outlined,
                                        label: order.dealerName,
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMetaRow(
                                        icon: Icons.directions_car_outlined,
                                        label: '${order.merk} ${order.model} • ${order.bodyTypeName}',
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMetaRow(
                                        icon: Icons.inventory_2_outlined,
                                        label: 'Jumlah: ${order.quantity} unit',
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMetaRow(
                                        icon: Icons.payments_outlined,
                                        label: order.formattedTotalPrice,
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMetaRow(
                                        icon: Icons.calendar_today_outlined,
                                        label: 'Dibuat pada ${order.createdAtLabel}',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildUnitMovementContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Keluar Masuk Unit',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            OutlinedButton(
              onPressed: _isUnitMovementLoading ? null : _fetchUnitMovementOrders,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.all(12),
              ),
              child: const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _unitMovementSearchController,
          decoration: InputDecoration(
            hintText: 'Cari SPK berdasarkan kode SPK, customer, dealer, merk, model, atau nomor rangka...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            filled: true,
            fillColor: Colors.grey.shade100,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isUnitMovementLoading
              ? const Center(child: CircularProgressIndicator())
              : _unitMovementErrorMessage != null
                  ? _UnitMovementErrorState(
                      message: _unitMovementErrorMessage!,
                      onRetry: _fetchUnitMovementOrders,
                    )
                  : _filteredUnitMovementOrders.isEmpty
                      ? const _UnitMovementEmptyState()
                      : RefreshIndicator(
                          onRefresh: _fetchUnitMovementOrders,
                          child: ListView.separated(
                            itemCount: _filteredUnitMovementOrders.length,
                            separatorBuilder: (context, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final order = _filteredUnitMovementOrders[index];
                              return _SpkTile(
                                order: order,
                                onTap: () => _UnitMovementDetailSheet.show(
                                  context,
                                  order,
                                  widget.authToken,
                                  onMovementSuccess: _fetchUnitMovementOrders,
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildMetaRow({required IconData icon, required String label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildTag(
    String text, {
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class OwnerHomeScreen extends StatefulWidget {
	const OwnerHomeScreen({
		super.key,
		this.userName,
		required this.authToken,
	});

	final String? userName;
	final String authToken;

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
	static String get _visitsEndpoint => ApiConfig.visitsEndpoint;
	static String get _purchaseOrdersEndpoint => ApiConfig.purchaseOrdersEndpoint;

	DashboardMenu _selectedMenu = DashboardMenu.visit;
	final List<DashboardMenu> _ownerMenus = [
		DashboardMenu.visit,
		DashboardMenu.spk,
	];

	// Visit data and filtering
	bool _isVisitLoading = false;
	String? _visitErrorMessage;
	List<VisitData> _visits = const [];
	List<VisitData> _filteredVisits = const [];
	DateTimeRange? _visitDateRange;
	String _visitFilterType = 'week'; // 'today', 'week', 'month', 'year', 'custom'

	// SPK data and filtering
	bool _isSpkLoading = false;
	String? _spkErrorMessage;
	List<PurchaseOrderData> _purchaseOrders = const [];
	List<PurchaseOrderData> _filteredPurchaseOrders = const [];
	DateTimeRange? _spkDateRange;
	String _spkFilterType = 'week'; // 'today', 'week', 'month', 'year', 'custom'

	final List<CustomerData> _customers = const [
		CustomerData(
			name: 'PT Nusantara Jaya',
			category: 'Enterprise',
			status: 'Aktif',
			lastActivity: '12 Nov 2025',
			customerTypeLabel: 'Customer Lama',
		),
		CustomerData(
			name: 'CV Maju Bersama',
			category: 'SME',
			status: 'Prospek',
			lastActivity: '08 Nov 2025',
			customerTypeLabel: 'Customer Baru',
		),
		CustomerData(
			name: 'PT Samudera Digital',
			category: 'Enterprise',
			status: 'Negosiasi',
			lastActivity: '03 Nov 2025',
			customerTypeLabel: 'Customer Lama',
		),
		CustomerData(
			name: 'PT Lentera Kreatif',
			category: 'Startup',
			status: 'Aktif',
			lastActivity: '01 Nov 2025',
			customerTypeLabel: 'Customer Baru',
		),
	];

	final List<UnitMovementData> _unitMovements = const [
		UnitMovementData(
			unitName: 'Crane XCT75',
			movementType: UnitMovementType.outbound,
			location: 'Proyek Dermaga Surabaya',
			timestamp: '09 Nov 2025, 09:30',
			notes: 'Pengiriman unit ke proyek dermaga',
		),
		UnitMovementData(
			unitName: 'Wheel Loader WA200',
			movementType: UnitMovementType.inbound,
			location: 'Gudang Utama Bandung',
			timestamp: '06 Nov 2025, 16:45',
			notes: 'Kembali dari penyewaan 2 minggu',
		),
	];

	@override
	void initState() {
		super.initState();
		_applyVisitFilter(); // This will fetch visits with current filter
		_fetchPurchaseOrders(filterType: _spkFilterType);
	}


	void _applyVisitFilter() {
		// For owner, fetch visits with filter parameters
		_fetchVisits(filterType: _visitFilterType, customRange: _visitDateRange);
	}


	Future<void> _fetchVisits({String? filterType, DateTimeRange? customRange}) async {
		if (!mounted) return;

		setState(() {
			_isVisitLoading = true;
			_visitErrorMessage = null;
		});

		try {
			// Build query parameters based on filter
			final queryParams = <String, String>{};
			
			if (filterType != null) {
				if (filterType == 'custom' && customRange != null) {
					queryParams['start_date'] = customRange.start.toIso8601String().split('T')[0];
					queryParams['end_date'] = customRange.end.toIso8601String().split('T')[0];
				} else {
					switch (filterType) {
						case 'today':
							queryParams['date_filter'] = 'today';
							break;
						case 'week':
							queryParams['date_filter'] = 'this_week';
							break;
						case 'month':
							queryParams['date_filter'] = 'this_month';
							break;
						case 'year':
							queryParams['date_filter'] = 'this_year';
							break;
					}
				}
			}

			final uri = queryParams.isEmpty 
				? Uri.parse(_visitsEndpoint)
				: Uri.parse(_visitsEndpoint).replace(queryParameters: queryParams);

			final response = await http.get(
				uri,
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				await _handleSessionExpired();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				final rawData = decoded['data'];
				final visits = rawData is List
						? rawData
								.whereType<Map<String, dynamic>>()
								.map(
									(visitJson) => VisitData.fromJson(
										visitJson,
										mediaBaseUrl: ApiConfig.baseUrl,
									),
								)
								.toList()
						: const <VisitData>[];

				if (!mounted) return;
				setState(() {
					_visits = visits;
					_filteredVisits = visits;
				});
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal memuat data kunjungan.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			if (!mounted) return;
			setState(() {
				_visitErrorMessage = error.message;
				_visits = const [];
				_filteredVisits = const [];
			});
		} on FormatException {
			if (!mounted) return;
			setState(() {
				_visitErrorMessage = 'Format data visit tidak valid.';
				_visits = const [];
				_filteredVisits = const [];
			});
		} catch (error) {
			if (!mounted) return;
			setState(() {
				_visitErrorMessage = 'Terjadi kesalahan: ${error.toString()}';
			});
		} finally {
			if (mounted) {
				setState(() {
					_isVisitLoading = false;
				});
			}
		}
	}

	Future<void> _fetchPurchaseOrders({String? filterType, DateTimeRange? customRange}) async {
		if (!mounted) return;

		setState(() {
			_isSpkLoading = true;
			_spkErrorMessage = null;
		});

		try {
			// Build query parameters based on filter
			final queryParams = <String, String>{};
			
			if (filterType != null) {
				if (filterType == 'custom' && customRange != null) {
					queryParams['start_date'] = customRange.start.toIso8601String().split('T')[0];
					queryParams['end_date'] = customRange.end.toIso8601String().split('T')[0];
				} else {
					switch (filterType) {
						case 'today':
							queryParams['date_filter'] = 'today';
							break;
						case 'week':
							queryParams['date_filter'] = 'this_week';
							break;
						case 'month':
							queryParams['date_filter'] = 'this_month';
							break;
						case 'year':
							queryParams['date_filter'] = 'this_year';
							break;
					}
				}
			}

			final uri = queryParams.isEmpty 
				? Uri.parse(_purchaseOrdersEndpoint)
				: Uri.parse(_purchaseOrdersEndpoint).replace(queryParameters: queryParams);

			final response = await http.get(
				uri,
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				await _handleSessionExpired();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				final raw = decoded['data'];
				final orders = raw is List
						? raw
								.map((item) => item is Map<String, dynamic>
										? PurchaseOrderData.fromJson(item)
										: null)
								.whereType<PurchaseOrderData>()
								.toList()
						: <PurchaseOrderData>[];
				setState(() {
					_purchaseOrders = orders;
					_filteredPurchaseOrders = orders;
				});
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal memuat data SPK.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			if (!mounted) return;
			setState(() {
				_spkErrorMessage = error.message;
				_purchaseOrders = const [];
				_filteredPurchaseOrders = const [];
			});
		} on FormatException {
			if (!mounted) return;
			setState(() {
				_spkErrorMessage = 'Format data SPK tidak valid.';
				_purchaseOrders = const [];
				_filteredPurchaseOrders = const [];
			});
		} catch (error) {
			if (!mounted) return;
			setState(() {
				_spkErrorMessage = 'Terjadi kesalahan: ${error.toString()}';
			});
		} finally {
			if (mounted) {
				setState(() {
					_isSpkLoading = false;
				});
			}
		}
	}

	Future<void> _handleSessionExpired([String? message]) async {
		if (!mounted) return;
		final messenger = ScaffoldMessenger.of(context);
		messenger
			..hideCurrentSnackBar()
			..showSnackBar(
				SnackBar(
					content: Text(
						message ?? 'Sesi login berakhir. Silakan login kembali.',
					),
				),
			);
		await _logout(context);
	}

	void _handleMenuTap(DashboardMenu menu) {
		setState(() {
			_selectedMenu = menu;
		});
	}

	Widget _buildSelectedContent() {
		switch (_selectedMenu) {
			case DashboardMenu.visit:
				return _OwnerVisitView(
					visitItems: _filteredVisits,
					isLoading: _isVisitLoading,
					errorMessage: _visitErrorMessage,
					filterType: _visitFilterType,
					dateRange: _visitDateRange,
					onFilterChanged: (filterType, dateRange) {
						setState(() {
							_visitFilterType = filterType;
							_visitDateRange = dateRange;
						});
						_applyVisitFilter();
					},
					onRefresh: () => _applyVisitFilter(),
					authToken: widget.authToken,
				);
			case DashboardMenu.customer:
				return _OwnerCustomerView(customers: _customers);
			case DashboardMenu.spk:
				return _OwnerSpkView(
					spkItems: _filteredPurchaseOrders,
					isLoading: _isSpkLoading,
					errorMessage: _spkErrorMessage,
					filterType: _spkFilterType,
					dateRange: _spkDateRange,
					onFilterChanged: (filterType, dateRange) {
						setState(() {
							_spkFilterType = filterType;
							_spkDateRange = dateRange;
						});
						_fetchPurchaseOrders(filterType: filterType, customRange: dateRange);
					},
					onRefresh: () => _fetchPurchaseOrders(filterType: _spkFilterType, customRange: _spkDateRange),
				);
			case DashboardMenu.unitMovement:
				return _OwnerUnitMovementView(unitMovements: _unitMovements);
		}
	}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepPurple, Colors.purple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.business_center_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Owner Dashboard',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.logout_outlined,
                color: Colors.black54,
              ),
              tooltip: 'Logout',
              onPressed: () => _logout(context),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact header with just title
            Row(
              children: [
                Text(
                  'Dashboard Owner',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_visits.length} Visit • ${_purchaseOrders.length} SPK',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _ownerMenus.length,
                separatorBuilder: (context, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final menu = _ownerMenus[index];
                  final isSelected = _selectedMenu == menu;
                  return GestureDetector(
                    onTap: () => _handleMenuTap(menu),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: 160,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? menu.accentColor : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? menu.accentColor.withValues(alpha: 0.3)
                              : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? menu.accentColor.withValues(alpha: 0.3)
                                : Colors.black.withValues(alpha: 0.08),
                            blurRadius: isSelected ? 12 : 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : menu.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              menu.icon,
                              color: isSelected ? Colors.white : menu.accentColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            menu.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            menu.subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.black54,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildSelectedContent()),
          ],
        ),
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit, required this.authToken});

  final VisitData visit;
  final String authToken;

  @override
  Widget build(BuildContext context) {
    final addressLabel = visit.dealerAddressLabel;
    final visitDateLabel =
        visit.visitDateLabel ?? 'Tanggal visit belum tersedia';
    final coordinateLabel = visit.coordinateLabel ?? 'Koordinat belum tersedia';
    final customerLabel = visit.customerName;
	final customerPhone = visit.customerPhone;

		return Material(
			color: Colors.transparent,
			child: InkWell(
				borderRadius: BorderRadius.circular(18),
				onTap: () => _VisitDetailSheet.show(context, visit, authToken),
				child: Container(
					padding: const EdgeInsets.all(18),
					decoration: BoxDecoration(
						color: Colors.white,
						borderRadius: BorderRadius.circular(18),
						border: Border.all(color: Colors.grey.shade200),
						boxShadow: [
							BoxShadow(
								color: Colors.black.withValues(alpha: 0.05),
								blurRadius: 12,
								offset: const Offset(0, 6),
							),
						],
					),
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Row(
								mainAxisAlignment: MainAxisAlignment.spaceBetween,
								children: [
									Expanded(
										child: Text(
											visit.displayDealerName,
											style: const TextStyle(
												fontSize: 16,
												fontWeight: FontWeight.w700,
											),
										),
									),
									if (visit.status != null && visit.status!.isNotEmpty)
										_StatusPill(status: visit.status!),
								],
							),
							const SizedBox(height: 12),
							_VisitMetaRow(
								icon: Icons.store_mall_directory_outlined,
								label: addressLabel,
							),
							const SizedBox(height: 8),
							_VisitMetaRow(
								icon: Icons.calendar_today_outlined,
								label: visitDateLabel,
							),
							const SizedBox(height: 8),
							_VisitMetaRow(
								icon: Icons.location_on_outlined,
								label: coordinateLabel,
							),
							if (customerLabel != null && customerLabel.isNotEmpty) ...[
								const SizedBox(height: 8),
								_VisitMetaRow(
									icon: Icons.person_outline,
									label: 'Customer: $customerLabel',
								),
							],
							if (customerPhone != null && customerPhone.isNotEmpty) ...[
								const SizedBox(height: 8),
								_VisitMetaRow(
									icon: Icons.phone_outlined,
									label: 'Telepon: $customerPhone',
								),
							],
						],
					),
				),
			),
		);
  }
}

class DealerData {
	const DealerData({
		required this.id,
		required this.name,
		this.phone,
		this.address,
	});

	final int id;
	final String name;
	final String? phone;
	final String? address;

	factory DealerData.fromJson(Map<String, dynamic> json) {
		return DealerData(
			id: _readInt(json['id']) ?? 0,
			name: _readNonEmptyString(json['name']) ??
					_readNonEmptyString(json['dealer_name']) ??
					'Dealer Tanpa Nama',
			phone: _readNonEmptyString(json['phone']) ??
					_readNonEmptyString(json['phone_number']) ??
					_readNonEmptyString(json['telp']),
			address: _readNonEmptyString(json['address']) ??
					_readNonEmptyString(json['alamat']) ??
					_readNonEmptyString(json['dealer_address']),
		);
	}
	static int? _readInt(dynamic value) {
		if (value == null) return null;
		if (value is int) return value;
		if (value is String) return int.tryParse(value);
		return null;
	}

	static String? _readNonEmptyString(dynamic value) {
		if (value == null) return null;
		final text = value.toString().trim();
		return text.isEmpty ? null : text;
	}
}

class _VisitCreationOptions extends StatelessWidget {
	const _VisitCreationOptions({
		required this.onSelectExisting,
		required this.onSelectNew,
	});

	final VoidCallback onSelectExisting;
	final VoidCallback onSelectNew;

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);

		return Padding(
			padding: EdgeInsets.only(
				left: 24,
				right: 24,
				top: 16,
				bottom: MediaQuery.of(context).padding.bottom + 24,
			),
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				mainAxisSize: MainAxisSize.min,
				children: [
					Text(
						'Buat Visit Baru',
						style: theme.textTheme.titleMedium?.copyWith(
									fontWeight: FontWeight.w700,
								) ??
								const TextStyle(
									fontSize: 18,
									fontWeight: FontWeight.w700,
								),
					),
					const SizedBox(height: 12),
					Text(
						'Pilih tipe dealer untuk proses visit.',
						style: theme.textTheme.bodyMedium?.copyWith(
									color: Colors.black54,
								) ??
								const TextStyle(
									fontSize: 14,
									color: Colors.black54,
								),
					),
					const SizedBox(height: 24),
					_VisitCreationOptionTile(
						icon: Icons.store_outlined,
						title: 'Dealer Lama',
						subtitle: 'Pilih dealer dari daftar yang sudah terdaftar.',
						onTap: onSelectExisting,
					),
					const SizedBox(height: 12),
					_VisitCreationOptionTile(
						icon: Icons.add_business_outlined,
						title: 'Dealer Baru',
						subtitle: 'Input data dealer dan customer baru.',
						onTap: onSelectNew,
					),
				],
			),
		);
	}
}

class _VisitCreationOptionTile extends StatelessWidget {
	const _VisitCreationOptionTile({
		required this.icon,
		required this.title,
		required this.subtitle,
		required this.onTap,
	});

	final IconData icon;
	final String title;
	final String subtitle;
	final VoidCallback onTap;

	@override
	Widget build(BuildContext context) {
		return Material(
			color: Colors.white,
			borderRadius: BorderRadius.circular(18),
			child: InkWell(
				borderRadius: BorderRadius.circular(18),
				onTap: onTap,
				child: Padding(
					padding: const EdgeInsets.all(18),
					child: Row(
						children: [
							Container(
								width: 48,
								height: 48,
								decoration: BoxDecoration(
									color: Colors.deepPurple.withValues(alpha: 0.08),
									borderRadius: BorderRadius.circular(16),
								),
								child: Icon(icon, color: Colors.deepPurple),
							),
							const SizedBox(width: 16),
							Expanded(
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
										Text(
											title,
											style: const TextStyle(
												fontSize: 16,
												fontWeight: FontWeight.w700,
											),
										),
										const SizedBox(height: 6),
										Text(
											subtitle,
											style: const TextStyle(
												fontSize: 13,
												color: Colors.black54,
											),
										),
									],
								),
							),
							const Icon(Icons.arrow_forward_ios_rounded,
									size: 16, color: Colors.black26),
						],
					),
				),
			),
		);
	}
}

class _DealerSelectionSheet extends StatefulWidget {
	const _DealerSelectionSheet({
		required this.authToken,
		required this.endpoint,
	});

	final String authToken;
	final String endpoint;

	@override
	State<_DealerSelectionSheet> createState() => _DealerSelectionSheetState();
}

class _DealerSelectionSheetState extends State<_DealerSelectionSheet> {
	final TextEditingController _searchController = TextEditingController();
	List<DealerData> _dealers = const [];
	List<DealerData> _filteredDealers = const [];
	bool _isLoading = true;
	String? _errorMessage;

	@override
	void initState() {
		super.initState();
		_searchController.addListener(_applyFilter);
		_loadDealers();
	}

	@override
	void dispose() {
		_searchController
			..removeListener(_applyFilter)
			..dispose();
		super.dispose();
	}

	Future<void> _loadDealers() async {
		setState(() {
			_isLoading = true;
			_errorMessage = null;
		});

		try {
			final response = await http.get(
				Uri.parse(widget.endpoint),
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				setState(() {
					_isLoading = false;
				});
				await _handleUnauthorized();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				final raw = decoded['data'];
				final dealers = raw is List
						? raw
								.whereType<Map<String, dynamic>>()
								.map(DealerData.fromJson)
								.toList()
						: <DealerData>[];
				setState(() {
					_dealers = dealers;
					_filteredDealers = dealers;
					_isLoading = false;
				});
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal memuat daftar dealer.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			setState(() {
				_errorMessage = error.message;
				_isLoading = false;
			});
		} on FormatException {
			setState(() {
				_errorMessage = 'Format data dealer tidak valid.';
				_isLoading = false;
			});
		} catch (error) {
			setState(() {
				_errorMessage = 'Terjadi kesalahan: ${error.toString()}';
				_isLoading = false;
			});
		}
	}

	void _applyFilter() {
		final query = _searchController.text.trim().toLowerCase();
		if (query.isEmpty) {
			setState(() {
				_filteredDealers = _dealers;
			});
			return;
		}

		setState(() {
			_filteredDealers = _dealers
					.where(
						(dealer) =>
								dealer.name.toLowerCase().contains(query) ||
								(dealer.address?.toLowerCase().contains(query) ?? false) ||
								(dealer.phone?.toLowerCase().contains(query) ?? false),
					)
					.toList();
		});
	}

	Future<void> _handleUnauthorized() async {
		if (!mounted) return;
		final messenger = ScaffoldMessenger.of(context);
		messenger
			..hideCurrentSnackBar()
			..showSnackBar(
				const SnackBar(
					content: Text('Sesi login berakhir. Silakan login kembali.'),
				),
			);
		await _logout(context);
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final bottomPadding = MediaQuery.of(context).padding.bottom + 24;

		return FractionallySizedBox(
			heightFactor: 0.9,
			child: Padding(
				padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
				child: Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						Row(
							mainAxisAlignment: MainAxisAlignment.spaceBetween,
							children: [
								Expanded(
									child: Text(
										'Pilih Dealer Lama',
										style: theme.textTheme.titleMedium?.copyWith(
													fontWeight: FontWeight.w700,
												) ??
												const TextStyle(
													fontSize: 18,
													fontWeight: FontWeight.w700,
												),
									),
								),
								IconButton(
									icon: const Icon(Icons.close),
									onPressed: () => Navigator.of(context).pop(),
								),
							],
						),
						const SizedBox(height: 8),
						Text(
							'Cari dan pilih dealer yang ingin dikunjungi.',
							style: theme.textTheme.bodyMedium?.copyWith(
										color: Colors.black54,
									) ??
									const TextStyle(
										fontSize: 14,
										color: Colors.black54,
									),
						),
						const SizedBox(height: 16),
						TextField(
							controller: _searchController,
							decoration: InputDecoration(
								hintText: 'Cari nama atau alamat dealer...',
								prefixIcon: const Icon(Icons.search),
								border: OutlineInputBorder(
									borderRadius: BorderRadius.circular(14),
								),
								filled: true,
								fillColor: Colors.grey.shade100,
							),
						),
						const SizedBox(height: 16),
						Expanded(
							child: _isLoading
									? const Center(child: CircularProgressIndicator())
									: _errorMessage != null
											? _DealerErrorState(
													message: _errorMessage!,
													onRetry: _loadDealers,
												)
											: _filteredDealers.isEmpty
													? const _DealerEmptyState()
													: RefreshIndicator(
															onRefresh: _loadDealers,
															child: ListView.separated(
																itemCount: _filteredDealers.length,
																separatorBuilder: (context, _) =>
																		const SizedBox(height: 12),
																itemBuilder: (context, index) {
																	final dealer = _filteredDealers[index];
																	return _DealerTile(
																		dealer: dealer,
																		onTap: () =>
																				Navigator.of(context).pop(dealer),
																	);
																},
															),
														),
						),
					],
				),
			),
		);
	}
}

class _DealerTile extends StatelessWidget {
	const _DealerTile({
		required this.dealer,
		required this.onTap,
	});

	final DealerData dealer;
	final VoidCallback onTap;

	@override
	Widget build(BuildContext context) {
			final parts = dealer.name
					.trim()
					.split(RegExp(r'\s+'))
					.where((part) => part.isNotEmpty)
					.toList();
			final initialsBuffer = StringBuffer();
			for (final part in parts.take(2)) {
				initialsBuffer.write(part[0].toUpperCase());
			}
			final initials = initialsBuffer.isEmpty ? '?' : initialsBuffer.toString();

		return Material(
			color: Colors.white,
			borderRadius: BorderRadius.circular(18),
			child: InkWell(
				borderRadius: BorderRadius.circular(18),
				onTap: onTap,
				child: Padding(
					padding: const EdgeInsets.all(18),
					child: Row(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							CircleAvatar(
								radius: 24,
								backgroundColor: Colors.deepPurple.withValues(alpha: 0.12),
								child: Text(
									initials.toUpperCase(),
									style: const TextStyle(
										color: Colors.deepPurple,
										fontWeight: FontWeight.w700,
									),
								),
							),
							const SizedBox(width: 16),
							Expanded(
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
										Text(
											dealer.name,
											style: const TextStyle(
												fontSize: 16,
												fontWeight: FontWeight.w700,
											),
										),
										if (dealer.address != null && dealer.address!.isNotEmpty) ...[
											const SizedBox(height: 6),
											Text(
												dealer.address!,
												style: const TextStyle(
													fontSize: 13,
													color: Colors.black87,
												),
											),
										],
										if (dealer.phone != null && dealer.phone!.isNotEmpty) ...[
											const SizedBox(height: 6),
											Row(
												children: [
													const Icon(Icons.phone, size: 14, color: Colors.black45),
													const SizedBox(width: 4),
													Text(
														dealer.phone!,
														style: const TextStyle(
															fontSize: 13,
															color: Colors.black54,
														),
													),
												],
											),
										],
									],
								),
							),
						],
					),
				),
			),
		);
	}
}

class _DealerErrorState extends StatelessWidget {
	const _DealerErrorState({
		required this.message,
		required this.onRetry,
	});

	final String message;
	final VoidCallback onRetry;

	@override
	Widget build(BuildContext context) {
		return Center(
			child: Column(
				mainAxisSize: MainAxisSize.min,
				children: [
					const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
					const SizedBox(height: 16),
					Padding(
						padding: const EdgeInsets.symmetric(horizontal: 16),
						child: Text(
							message,
							textAlign: TextAlign.center,
							style: const TextStyle(fontSize: 14, color: Colors.black87),
						),
					),
					const SizedBox(height: 16),
					OutlinedButton.icon(
						onPressed: onRetry,
						icon: const Icon(Icons.refresh_outlined),
						label: const Text('Coba Lagi'),
					),
				],
			),
		);
	}
}

class _DealerEmptyState extends StatelessWidget {
	const _DealerEmptyState();

	@override
	Widget build(BuildContext context) {
		return ListView(
			physics: const AlwaysScrollableScrollPhysics(),
			children: const [
				SizedBox(height: 80),
				Icon(Icons.store_outlined, size: 64, color: Colors.black26),
				SizedBox(height: 12),
				Center(
					child: Text(
						'Belum ada data dealer tersedia.',
						style: TextStyle(fontSize: 14, color: Colors.black54),
					),
				),
			],
		);
	}
}

class _UnitMovementErrorState extends StatelessWidget {
	const _UnitMovementErrorState({
		required this.message,
		required this.onRetry,
	});

	final String message;
	final VoidCallback onRetry;

	@override
	Widget build(BuildContext context) {
		return Center(
			child: Column(
				mainAxisSize: MainAxisSize.min,
				children: [
					const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
					const SizedBox(height: 16),
					Padding(
						padding: const EdgeInsets.symmetric(horizontal: 16),
						child: Text(
							message,
							textAlign: TextAlign.center,
							style: const TextStyle(fontSize: 14, color: Colors.black87),
						),
					),
					const SizedBox(height: 16),
					OutlinedButton.icon(
						onPressed: onRetry,
						icon: const Icon(Icons.refresh_outlined),
						label: const Text('Coba Lagi'),
					),
				],
			),
		);
	}
}

class _UnitMovementEmptyState extends StatelessWidget {
	const _UnitMovementEmptyState();

	@override
	Widget build(BuildContext context) {
		return ListView(
			physics: const AlwaysScrollableScrollPhysics(),
			children: const [
				SizedBox(height: 80),
				Icon(Icons.local_shipping_outlined, size: 64, color: Colors.black26),
				SizedBox(height: 12),
				Center(
					child: Text(
						'Belum ada SPK yang dapat dipindahkan.',
						style: TextStyle(fontSize: 14, color: Colors.black54),
					),
				),
			],
		);
	}
}

class _NewDealerVisitSheet extends StatefulWidget {
	const _NewDealerVisitSheet({
		required this.onCompleted,
	});

	final ValueChanged<VisitSubmissionPayload> onCompleted;

	@override
	State<_NewDealerVisitSheet> createState() => _NewDealerVisitSheetState();
}

class _ExistingDealerVisitSheet extends StatefulWidget {
	const _ExistingDealerVisitSheet({
		required this.dealer,
		required this.onCompleted,
	});

	final DealerData dealer;
	final ValueChanged<VisitSubmissionPayload> onCompleted;

	@override
	State<_ExistingDealerVisitSheet> createState() => _ExistingDealerVisitSheetState();
}

class _ExistingDealerVisitSheetState extends State<_ExistingDealerVisitSheet> {
	final ImagePicker _picker = ImagePicker();
	bool _isProcessing = false;

	Future<void> _handleSubmit() async {
		if (_isProcessing) return;

		final shouldProceed = await showModalBottomSheet<bool>(
			context: context,
			useSafeArea: true,
			isScrollControlled: true,
			showDragHandle: true,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
			),
			builder: (_) => const _SelfieInstructionSheet(),
		);

		if (shouldProceed != true || !mounted) {
			return;
		}

		setState(() {
			_isProcessing = true;
		});

		try {
			final hasPermission = await _ensureLocationPermission();
			if (!hasPermission || !mounted) {
				return;
			}

			final position = await Geolocator.getCurrentPosition(
				desiredAccuracy: LocationAccuracy.high,
			);

			final selfie = await _picker.pickImage(
				source: ImageSource.camera,
				preferredCameraDevice: CameraDevice.front,
				imageQuality: 80,
			);

			if (selfie == null) {
				if (!mounted) return;
				ScaffoldMessenger.of(context).showSnackBar(
					const SnackBar(content: Text('Selfie dibatalkan. Visit belum disimpan.')),
				);
				return;
			}

			final payload = VisitSubmissionPayload(
				type: VisitDealerType.existing,
				dealer: widget.dealer,
				selfie: selfie,
				latitude: position.latitude,
				longitude: position.longitude,
			);

			widget.onCompleted(payload);
		} on PlatformException catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Gagal membuka kamera: ${error.message ?? error.code}')),
			);
		} catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Terjadi kesalahan: $error')),
			);
		} finally {
			if (mounted) {
				setState(() {
					_isProcessing = false;
				});
			}
		}
	}

	Future<bool> _ensureLocationPermission() async {
		final serviceEnabled = await Geolocator.isLocationServiceEnabled();
		if (!serviceEnabled) {
			if (!mounted) return false;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Aktifkan layanan lokasi untuk melanjutkan.'),
				),
			);
			return false;
		}

		var permission = await Geolocator.checkPermission();
		if (permission == LocationPermission.denied) {
			permission = await Geolocator.requestPermission();
		}

		if (permission == LocationPermission.denied ||
				permission == LocationPermission.deniedForever) {
			if (!mounted) return false;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Izin lokasi diperlukan untuk mencatat koordinat visit.'),
				),
			);
			return false;
		}

		return true;
	}

	@override
	Widget build(BuildContext context) {
		final bottomPadding = MediaQuery.of(context).viewInsets.bottom + 24;

		return Padding(
			padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
			child: SingleChildScrollView(
				child: Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						Row(
							mainAxisAlignment: MainAxisAlignment.spaceBetween,
							children: [
								const Text(
									'Visit Dealer Lama',
									style: TextStyle(
										fontSize: 20,
										fontWeight: FontWeight.bold,
									),
								),
								IconButton(
									icon: const Icon(Icons.close),
									onPressed: () => Navigator.of(context).pop(),
								),
							],
						),
						const SizedBox(height: 12),
						const Text(
							'Dealer yang dipilih akan menerima kunjungan. Pastikan data dealer sudah benar sebelum melanjutkan.',
							style: TextStyle(fontSize: 14, color: Colors.black54),
						),
						const SizedBox(height: 24),
						_DealerSummaryCard(dealer: widget.dealer),
						const SizedBox(height: 24),
						SizedBox(
							width: double.infinity,
							height: 52,
							child: ElevatedButton.icon(
								onPressed: _isProcessing ? null : _handleSubmit,
								icon: _isProcessing
										? const SizedBox(
												width: 18,
												height: 18,
												child: CircularProgressIndicator(
													strokeWidth: 2,
													color: Colors.white,
												),
											)
										: const Icon(Icons.verified_user_outlined),
								label: Text(_isProcessing ? 'Memproses...' : 'Simpan & Ambil Selfie'),
								style: ElevatedButton.styleFrom(
									backgroundColor: Colors.deepPurple,
									foregroundColor: Colors.white,
									shape: RoundedRectangleBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
							),
						),
					],
				),
			),
		);
	}
}

class _DealerSummaryCard extends StatelessWidget {
	const _DealerSummaryCard({required this.dealer});

	final DealerData dealer;

	@override
	Widget build(BuildContext context) {
		return Container(
			width: double.infinity,
			padding: const EdgeInsets.all(18),
			decoration: BoxDecoration(
				color: Colors.deepPurple.withValues(alpha: 0.06),
				borderRadius: BorderRadius.circular(18),
			),
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Text(
						dealer.name,
						style: const TextStyle(
							fontSize: 16,
							fontWeight: FontWeight.w700,
							color: Colors.deepPurple,
						),
					),
					if (dealer.address != null && dealer.address!.isNotEmpty) ...[
						const SizedBox(height: 8),
						Row(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
								const Icon(Icons.place_outlined, size: 16, color: Colors.black54),
								const SizedBox(width: 6),
								Expanded(
									child: Text(
										dealer.address!,
										style: const TextStyle(fontSize: 13, color: Colors.black87),
									),
								),
							],
						),
					],
					if (dealer.phone != null && dealer.phone!.isNotEmpty) ...[
						const SizedBox(height: 8),
						Row(
							children: [
								const Icon(Icons.phone, size: 16, color: Colors.black54),
								const SizedBox(width: 6),
								Text(
									dealer.phone!,
									style: const TextStyle(fontSize: 13, color: Colors.black87),
								),
							],
						),
					],
				],
			),
		);
	}
}
class _NewDealerVisitSheetState extends State<_NewDealerVisitSheet> {
	final _formKey = GlobalKey<FormState>();
	final TextEditingController _customerNameController = TextEditingController();
	final TextEditingController _customerAddressController = TextEditingController();
	final TextEditingController _customerPhoneController = TextEditingController();
	final TextEditingController _dealerNameController = TextEditingController();
	final TextEditingController _dealerPhoneController = TextEditingController();
	final TextEditingController _dealerAddressController = TextEditingController();

	final ImagePicker _picker = ImagePicker();
	bool _isProcessing = false;

	@override
	void dispose() {
		_customerNameController.dispose();
		_customerAddressController.dispose();
		_customerPhoneController.dispose();
		_dealerNameController.dispose();
		_dealerPhoneController.dispose();
		_dealerAddressController.dispose();
		super.dispose();
	}

	Future<void> _handleSubmit() async {
		if (_isProcessing) return;
		if (!_formKey.currentState!.validate()) {
			return;
		}

		final shouldProceed = await showModalBottomSheet<bool>(
			context: context,
			useSafeArea: true,
			isScrollControlled: true,
			showDragHandle: true,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
			),
			builder: (_) => const _SelfieInstructionSheet(),
		);

		if (shouldProceed != true || !mounted) {
			return;
		}

		setState(() {
			_isProcessing = true;
		});

		try {
			final hasPermission = await _ensureLocationPermission();
			if (!hasPermission || !mounted) {
				return;
			}

			final position = await Geolocator.getCurrentPosition(
				desiredAccuracy: LocationAccuracy.high,
			);

			final selfie = await _picker.pickImage(
				source: ImageSource.camera,
				preferredCameraDevice: CameraDevice.front,
				imageQuality: 80,
			);

			if (selfie == null) {
				if (!mounted) return;
				ScaffoldMessenger.of(context).showSnackBar(
					const SnackBar(content: Text('Selfie dibatalkan. Visit belum disimpan.')),
				);
				return;
			}

			final payload = VisitSubmissionPayload(
				type: VisitDealerType.newDealer,
				customerName: _customerNameController.text.trim(),
				customerAddress: _customerAddressController.text.trim(),
				customerPhone: _customerPhoneController.text.trim(),
				customDealerName: _dealerNameController.text.trim(),
				customDealerPhone: _dealerPhoneController.text.trim(),
				customDealerAddress: _dealerAddressController.text.trim(),
				selfie: selfie,
				latitude: position.latitude,
				longitude: position.longitude,
			);

			widget.onCompleted(payload);
		} on PlatformException catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Gagal membuka kamera: ${error.message ?? error.code}')),
			);
		} catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Terjadi kesalahan: $error')),
			);
		} finally {
			if (mounted) {
				setState(() {
					_isProcessing = false;
				});
			}
		}
	}

	Future<bool> _ensureLocationPermission() async {
		final serviceEnabled = await Geolocator.isLocationServiceEnabled();
		if (!serviceEnabled) {
			if (!mounted) return false;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Aktifkan layanan lokasi untuk melanjutkan.'),
				),
			);
			return false;
		}

		var permission = await Geolocator.checkPermission();
		if (permission == LocationPermission.denied) {
			permission = await Geolocator.requestPermission();
		}

		if (permission == LocationPermission.denied ||
				permission == LocationPermission.deniedForever) {
			if (!mounted) return false;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Izin lokasi diperlukan untuk mencatat koordinat visit.'),
				),
			);
			return false;
		}
		return true;
	}

	@override
	Widget build(BuildContext context) {
		final bottomPadding = MediaQuery.of(context).viewInsets.bottom + 24;

		return Padding(
			padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
			child: SingleChildScrollView(
				child: Form(
					key: _formKey,
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Row(
								mainAxisAlignment: MainAxisAlignment.spaceBetween,
								children: [
									const Text(
										'Visit Dealer Baru',
										style: TextStyle(
											fontSize: 20,
											fontWeight: FontWeight.bold,
										),
									),
									IconButton(
										icon: const Icon(Icons.close),
										onPressed: () => Navigator.of(context).pop(),
									),
								],
							),
							const SizedBox(height: 12),
							const Text(
								'Lengkapi data customer dan dealer sebelum melakukan selfie verifikasi.',
								style: TextStyle(fontSize: 14, color: Colors.black54),
							),
							const SizedBox(height: 24),
							const Text(
								'Data Customer',
								style: TextStyle(
									fontSize: 14,
									fontWeight: FontWeight.w700,
								),
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _customerNameController,
								textInputAction: TextInputAction.next,
								decoration: InputDecoration(
									labelText: 'Nama Customer',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Nama customer wajib diisi';
									}
									return null;
								},
							),
							const SizedBox(height: 16),
							TextFormField(
								controller: _customerPhoneController,
								textInputAction: TextInputAction.next,
								keyboardType: TextInputType.phone,
								decoration: InputDecoration(
									labelText: 'Nomor Telepon Customer',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Nomor telepon wajib diisi';
									}
									if (value.trim().length < 8) {
										return 'Nomor telepon tidak valid';
									}
									return null;
								},
							),
							const SizedBox(height: 16),
							TextFormField(
								controller: _customerAddressController,
								textInputAction: TextInputAction.next,
								maxLines: 2,
								decoration: InputDecoration(
									labelText: 'Alamat Customer',
									alignLabelWithHint: true,
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Alamat customer wajib diisi';
									}
									return null;
								},
							),
							const SizedBox(height: 24),
							const Text(
								'Data Dealer',
								style: TextStyle(
									fontSize: 14,
									fontWeight: FontWeight.w700,
								),
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _dealerNameController,
								textInputAction: TextInputAction.next,
								decoration: InputDecoration(
									labelText: 'Nama Dealer',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Nama dealer wajib diisi';
									}
									return null;
								},
							),
							const SizedBox(height: 16),
							TextFormField(
								controller: _dealerPhoneController,
								textInputAction: TextInputAction.next,
								keyboardType: TextInputType.phone,
								decoration: InputDecoration(
									labelText: 'Nomor Telepon Dealer',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Nomor telepon dealer wajib diisi';
									}
									if (value.trim().length < 8) {
										return 'Nomor telepon dealer tidak valid';
									}
									return null;
								},
							),
							const SizedBox(height: 16),
							TextFormField(
								controller: _dealerAddressController,
								maxLines: 2,
								decoration: InputDecoration(
									labelText: 'Alamat Dealer',
									alignLabelWithHint: true,
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Alamat dealer wajib diisi';
									}
									return null;
								},
							),
							const SizedBox(height: 24),
							SizedBox(
								width: double.infinity,
								height: 52,
								child: ElevatedButton.icon(
									onPressed: _isProcessing ? null : _handleSubmit,
									icon: _isProcessing
											? const SizedBox(
													width: 18,
													height: 18,
													child: CircularProgressIndicator(
														strokeWidth: 2,
														color: Colors.white,
													),
												)
											: const Icon(Icons.verified_user_outlined),
									label: Text(_isProcessing ? 'Memproses...' : 'Simpan & Ambil Selfie'),
									style: ElevatedButton.styleFrom(
										backgroundColor: Colors.deepPurple,
										foregroundColor: Colors.white,
										shape: RoundedRectangleBorder(
											borderRadius: BorderRadius.circular(12),
										),
									),
								),
							),
						],
					),
				),
			),
		);
	}
}

class _SelfieInstructionSheet extends StatelessWidget {
	const _SelfieInstructionSheet();

	@override
	Widget build(BuildContext context) {
		return Padding(
			padding: EdgeInsets.only(
				left: 24,
				right: 24,
				top: 16,
				bottom: MediaQuery.of(context).padding.bottom + 24,
			),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Center(
						child: Container(
							width: 48,
							height: 4,
							margin: const EdgeInsets.only(bottom: 24),
							decoration: BoxDecoration(
								color: Colors.grey.shade300,
								borderRadius: BorderRadius.circular(2),
							),
						),
					),
					Row(
						mainAxisAlignment: MainAxisAlignment.spaceBetween,
						children: [
							const Expanded(
								child: Text(
									'Silakan lakukan selfie untuk verifikasi lokasi',
									style: TextStyle(
										fontSize: 18,
										fontWeight: FontWeight.bold,
									),
								),
							),
							IconButton(
								onPressed: () => Navigator.of(context).pop(false),
								icon: const Icon(Icons.close),
							),
						],
					),
					const SizedBox(height: 16),
					const _InstructionBullet(text: 'Tekan tombol mulai untuk memulai proses.'),
					const _InstructionBullet(text: 'Pastikan wajah Anda berada di dalam bingkai.'),
					const _InstructionBullet(
						text: 'Hindari memakai masker, kacamata hitam, helm, atau topi.',
					),
					const _InstructionBullet(
						text: 'Pastikan hanya satu wajah yang terdeteksi di dalam frame.',
					),
					const SizedBox(height: 24),
					FilledButton(
						onPressed: () => Navigator.of(context).pop(true),
						style: FilledButton.styleFrom(
							backgroundColor: Colors.deepPurple,
							foregroundColor: Colors.white,
							minimumSize: const Size.fromHeight(52),
							shape: RoundedRectangleBorder(
								borderRadius: BorderRadius.circular(14),
							),
						),
						child: const Text('Mulai Selfie'),
					),
				],
			),
		);
	}
}

class _InstructionBullet extends StatelessWidget {
	const _InstructionBullet({required this.text});

	final String text;

	@override
	Widget build(BuildContext context) {
		return Padding(
			padding: const EdgeInsets.only(bottom: 12),
			child: Row(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					const Icon(Icons.check_circle_outline,
							size: 18, color: Colors.deepPurple),
					const SizedBox(width: 8),
					Expanded(
						child: Text(
							text,
							style: const TextStyle(fontSize: 14, color: Colors.black87),
						),
					),
				],
			),
		);
	}
}

class _VisitMetaRow extends StatelessWidget {
  const _VisitMetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

enum VisitDealerType { existing, newDealer }

class VisitSubmissionPayload {
	const VisitSubmissionPayload({
		required this.type,
		this.dealer,
		this.customerName,
		this.customerAddress,
		this.customerPhone,
		this.customDealerName,
		this.customDealerPhone,
		this.customDealerAddress,
		required this.selfie,
		required this.latitude,
		required this.longitude,
	});

	final VisitDealerType type;
	final DealerData? dealer;
	final String? customerName;
	final String? customerAddress;
	final String? customerPhone;
	final String? customDealerName;
	final String? customDealerPhone;
	final String? customDealerAddress;
	final XFile selfie;
	final double latitude;
	final double longitude;
}

class _VisitDetailSheet extends StatelessWidget {
	const _VisitDetailSheet({required this.visit, required this.authToken});

	final VisitData visit;
	final String authToken;

	static Future<void> show(BuildContext context, VisitData visit, String authToken) {
		return showModalBottomSheet<void>(
			context: context,
			isScrollControlled: true,
			backgroundColor: Colors.transparent,
			builder: (context) => _VisitDetailSheet(visit: visit, authToken: authToken),
		);
	}

		Future<void> _copyToClipboard(
			BuildContext context,
			String value, {
			required String successMessage,
		}) async {
			final messenger = ScaffoldMessenger.maybeOf(context);
			if (messenger == null) {
				return;
			}
			await Clipboard.setData(ClipboardData(text: value));
			messenger
				..hideCurrentSnackBar()
				..showSnackBar(
					SnackBar(
						content: Text(successMessage),
						behavior: SnackBarBehavior.floating,
						duration: const Duration(seconds: 2),
					),
				);
	}

		Future<void> _openGoogleMaps(BuildContext context) async {
			final latitude = visit.latitude;
			final longitude = visit.longitude;
			final messenger = ScaffoldMessenger.maybeOf(context);

			if (latitude == null || longitude == null) {
				messenger
					?..hideCurrentSnackBar()
					..showSnackBar(
						const SnackBar(
							content: Text('Koordinat visit tidak tersedia.'),
						),
					);
				return;
			}

			final uri = Uri.parse(
				'https://www.google.com/maps?q=${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}',
			);

			final launched = await launchUrl(
				uri,
				mode: LaunchMode.externalApplication,
			);

			if (!launched) {
				messenger
					?..hideCurrentSnackBar()
					..showSnackBar(
						const SnackBar(
							content: Text('Tidak dapat membuka Google Maps.'),
						),
					);
			}
		}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final coordinateLabel = visit.coordinateLabel;
		final customerLabel = visit.customerName;
		final customerPhone = visit.customerPhone;
		final visitDateLabel = visit.visitDateLabel;
		final statusLabel = visit.status;

		return FractionallySizedBox(
			heightFactor: 0.88,
			child: ClipRRect(
				borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
				child: Material(
					color: Colors.white,
					child: SafeArea(
						top: false,
						child: Column(
							children: [
								const SizedBox(height: 12),
								Container(
									width: 44,
									height: 4,
									decoration: BoxDecoration(
										color: Colors.black26,
										borderRadius: BorderRadius.circular(16),
									),
								),
								Expanded(
									child: SingleChildScrollView(
										padding: EdgeInsets.fromLTRB(
											24,
											24,
											24,
											24 + MediaQuery.of(context).padding.bottom,
										),
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												Text(
													'Detail Visit',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
																color: Colors.deepPurple,
															) ??
															const TextStyle(
																fontSize: 18,
																fontWeight: FontWeight.w700,
																color: Colors.deepPurple,
															),
												),
												const SizedBox(height: 18),
												Row(
													crossAxisAlignment: CrossAxisAlignment.start,
													children: [
														Expanded(
															child: Text(
																visit.displayDealerName,
																style: theme.textTheme.headlineSmall?.copyWith(
																			fontSize: 22,
																			fontWeight: FontWeight.w700,
																		) ??
																		const TextStyle(
																			fontSize: 22,
																			fontWeight: FontWeight.w700,
																		),
															),
														),
														if (statusLabel != null && statusLabel.isNotEmpty)
															Padding(
																padding: const EdgeInsets.only(left: 12),
																child: _StatusPill(status: statusLabel),
															),
													],
												),
												const SizedBox(height: 24),
												_VisitDetailItem(
													icon: Icons.store_mall_directory_outlined,
													title: 'Alamat Dealer',
													value: visit.dealerAddressLabel,
												),
												_VisitDetailItem(
													icon: Icons.calendar_month_outlined,
													title: 'Tanggal Visit',
													value: visitDateLabel ?? 'Tanggal visit belum tersedia',
												),
												_VisitDetailItem(
													icon: Icons.location_on_outlined,
													title: 'Koordinat',
													value: coordinateLabel ?? 'Koordinat belum tersedia',
													action: coordinateLabel != null
															? IconButton(
																	icon: const Icon(Icons.copy_rounded),
																	tooltip: 'Salin koordinat',
																	onPressed: () => _copyToClipboard(
																		context,
																		coordinateLabel,
																	successMessage: 'Koordinat berhasil disalin ke clipboard',
																	),
																)
															: null,
												),
												if (customerLabel != null && customerLabel.isNotEmpty)
													_VisitDetailItem(
														icon: Icons.person_outline,
														title: 'Customer',
														value: customerLabel,
													),
												if (customerPhone != null && customerPhone.isNotEmpty)
													_VisitDetailItem(
														icon: Icons.phone_outlined,
														title: 'Telepon Customer',
														value: customerPhone,
														action: IconButton(
															icon: const Icon(Icons.copy_rounded),
															tooltip: 'Salin nomor telepon',
															onPressed: () => _copyToClipboard(
																context,
																customerPhone,
																successMessage: 'Nomor telepon berhasil disalin ke clipboard',
															),
														),
													),
												if (visit.notes != null && visit.notes!.isNotEmpty)
													_VisitDetailItem(
														icon: Icons.note_alt_outlined,
														title: 'Catatan Visit',
														value: visit.notes!,
													),
												if (visit.hasSelfie) ...[
													const SizedBox(height: 28),
													_VisitSelfieSection(visit: visit, authToken: authToken),
												],
												if (visit.latitude != null && visit.longitude != null) ...[
													const SizedBox(height: 28),
													_VisitMapSection(
														latitude: visit.latitude!,
														longitude: visit.longitude!,
														coordinateLabel: coordinateLabel,
													),
													const SizedBox(height: 16),
													FilledButton.icon(
														onPressed: () => _openGoogleMaps(context),
														style: FilledButton.styleFrom(
															minimumSize: const Size.fromHeight(52),
															backgroundColor: Colors.deepPurple,
															foregroundColor: Colors.white,
															shape: RoundedRectangleBorder(
																borderRadius: BorderRadius.circular(16),
															),
														),
														icon: const Icon(Icons.map_outlined),
														label: const Text('Buka di Google Maps'),
													),
												],
											],
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

class _VisitDetailItem extends StatelessWidget {
	const _VisitDetailItem({
		required this.icon,
		required this.title,
		required this.value,
		this.action,
	});

	final IconData icon;
	final String title;
	final String value;
	final Widget? action;

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);

		return Padding(
			padding: const EdgeInsets.symmetric(vertical: 12),
			child: Row(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Container(
						padding: const EdgeInsets.all(10),
						decoration: BoxDecoration(
							color: Colors.deepPurple.withValues(alpha: 0.08),
							borderRadius: BorderRadius.circular(14),
						),
						child: Icon(
							icon,
							size: 20,
							color: Colors.deepPurple,
						),
					),
					const SizedBox(width: 12),
					Expanded(
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
								Text(
									title,
									style: theme.textTheme.labelSmall?.copyWith(
												color: Colors.black54,
												fontWeight: FontWeight.w600,
												letterSpacing: 0.2,
											) ??
											const TextStyle(
												fontSize: 12,
												color: Colors.black54,
												fontWeight: FontWeight.w600,
											),
								),
								const SizedBox(height: 6),
								SelectableText(
									value,
									style: theme.textTheme.bodyMedium?.copyWith(
												fontSize: 15,
												fontWeight: FontWeight.w600,
												color: Colors.black87,
											) ??
											const TextStyle(
												fontSize: 15,
												fontWeight: FontWeight.w600,
												color: Colors.black87,
											),
								),
							],
						),
					),
					if (action != null) ...[
						const SizedBox(width: 4),
						action!,
					],
				],
			),
		);
	}
}

class _VisitSelfieSection extends StatefulWidget {
	const _VisitSelfieSection({required this.visit, required this.authToken});

	final VisitData visit;
	final String authToken;

	@override
	State<_VisitSelfieSection> createState() => _VisitSelfieSectionState();
}

class _VisitSelfieSectionState extends State<_VisitSelfieSection> {
	Uint8List? _imageBytes;
	bool _isLoading = true;
	String? _errorMessage;

	@override
	void initState() {
		super.initState();
		_loadImage();
	}

	Future<void> _loadImage() async {
		final mediaUrl = widget.visit.selfieUrl ?? widget.visit.selfieThumbnailUrl;
		if (mediaUrl == null || mediaUrl.isEmpty) {
			setState(() {
				_isLoading = false;
				_errorMessage = 'URL gambar tidak tersedia';
			});
			return;
		}

		// Clean URL: replace invalid characters
		final cleanUrl = mediaUrl.replaceAll('|', 'l'); // Fix common typo | -> l

		try {
			if (kDebugMode) {
				print('🔧 Loading image from: $cleanUrl (original: $mediaUrl)');
			}

			final response = await http.get(
				Uri.parse(cleanUrl),
				headers: {
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 200) {
				setState(() {
					_imageBytes = response.bodyBytes;
					_isLoading = false;
				});
				if (kDebugMode) {
					print('🔧 Image loaded successfully, size: ${response.bodyBytes.length} bytes');
				}
			} else {
				setState(() {
					_isLoading = false;
					_errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
				});
				if (kDebugMode) {
					print('🔧 Image load failed: HTTP ${response.statusCode}');
					print('🔧 Response body: ${response.body}');
				}
			}
		} catch (error) {
			setState(() {
				_isLoading = false;
				_errorMessage = 'Error: $error';
			});
			if (kDebugMode) {
				print('🔧 Image load error: $error');
			}
		}
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final timestamp = widget.visit.selfieTakenAtLabel;

		Widget mediaWidget;
		if (_isLoading) {
			mediaWidget = const _VisitPhotoLoading();
		} else if (_imageBytes != null) {
			mediaWidget = Stack(
				fit: StackFit.expand,
				children: [
					Image.memory(
						_imageBytes!,
						fit: BoxFit.cover,
						filterQuality: FilterQuality.medium,
					),
					if (timestamp != null)
						Positioned(
							left: 12,
							bottom: 12,
							child: Container(
								padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
								decoration: BoxDecoration(
									color: Colors.black.withValues(alpha: 0.6),
									borderRadius: BorderRadius.circular(12),
								),
								child: Row(
									mainAxisSize: MainAxisSize.min,
									children: [
										const Icon(
											Icons.access_time,
											size: 14,
											color: Colors.white,
										),
										const SizedBox(width: 6),
										Text(
											timestamp,
											style: const TextStyle(
												fontSize: 12,
												fontWeight: FontWeight.w600,
												color: Colors.white,
											),
										),
									],
								),
							),
						),
				],
			);
		} else {
			mediaWidget = _VisitPlaceholderCard(
				icon: Icons.broken_image_outlined,
				message: _errorMessage ?? 'Foto selfie gagal dimuat.',
			);
		}

		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				Text(
					widget.visit.selfieDisplayLabel,
					style: theme.textTheme.titleMedium?.copyWith(
						fontWeight: FontWeight.w700,
					) ??
					const TextStyle(
						fontSize: 16,
						fontWeight: FontWeight.w700,
					),
				),
				const SizedBox(height: 12),
				ClipRRect(
					borderRadius: BorderRadius.circular(20),
					child: AspectRatio(
						aspectRatio: 4 / 3,
						child: mediaWidget,
					),
				),
			],
		);
	}
}

class _VisitPhotoLoading extends StatelessWidget {
	const _VisitPhotoLoading();

	@override
	Widget build(BuildContext context) {
		return Container(
			color: Colors.black12,
			alignment: Alignment.center,
			child: const SizedBox(
				width: 32,
				height: 32,
				child: CircularProgressIndicator(
					strokeWidth: 3,
					color: Colors.deepPurple,
				),
			),
		);
	}
}

class _VisitPlaceholderCard extends StatelessWidget {
	const _VisitPlaceholderCard({
		required this.icon,
		required this.message,
	});

	final IconData icon;
	final String message;

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		return Container(
			color: Colors.grey.shade100,
			alignment: Alignment.center,
			padding: const EdgeInsets.symmetric(horizontal: 24),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				mainAxisAlignment: MainAxisAlignment.center,
				children: [
					Icon(icon, size: 46, color: Colors.black38),
					const SizedBox(height: 12),
					Text(
						message,
						textAlign: TextAlign.center,
						style: theme.textTheme.bodySmall?.copyWith(
									color: Colors.black54,
									fontWeight: FontWeight.w600,
								) ??
								const TextStyle(
									fontSize: 13,
									color: Colors.black54,
									fontWeight: FontWeight.w600,
								),
					),
				],
			),
		);
	}
}

class _VisitMapSection extends StatelessWidget {
	const _VisitMapSection({
		required this.latitude,
		required this.longitude,
		this.coordinateLabel,
	});

	final double latitude;
	final double longitude;
	final String? coordinateLabel;

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final point = LatLng(latitude, longitude);

		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				Text(
					'Lokasi Visit di Peta',
					style: theme.textTheme.titleMedium?.copyWith(
								fontWeight: FontWeight.w700,
							) ??
							const TextStyle(
								fontSize: 16,
								fontWeight: FontWeight.w700,
							),
				),
				const SizedBox(height: 12),
				ClipRRect(
					borderRadius: BorderRadius.circular(20),
					child: SizedBox(
						height: 240,
						child: FlutterMap(
							options: MapOptions(
								initialCenter: point,
								initialZoom: 16,
								interactionOptions: const InteractionOptions(
									flags: InteractiveFlag.pinchZoom |
											InteractiveFlag.drag |
											InteractiveFlag.doubleTapZoom,
								),
							),
							children: [
								TileLayer(
									urlTemplate:
											'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
									userAgentPackageName: 'com.ska.app',
								),
												MarkerLayer(
													markers: [
														Marker(
															width: 110,
															height: 110,
															point: point,
															alignment: Alignment.topCenter,
															child: _VisitMapMarker(
																label: coordinateLabel,
															),
														),
													],
												),
								RichAttributionWidget(
									attributions: [
										TextSourceAttribution('© OpenStreetMap contributors'),
									],
								),
							],
						),
					),
				),
			],
		);
	}
}

class _VisitMapMarker extends StatelessWidget {
	const _VisitMapMarker({this.label});

	final String? label;

	@override
	Widget build(BuildContext context) {
		return Column(
			mainAxisSize: MainAxisSize.min,
			children: [
				if (label != null && label!.isNotEmpty)
					Container(
						padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
						constraints: const BoxConstraints(maxWidth: 120),
						decoration: BoxDecoration(
							color: Colors.white,
							borderRadius: BorderRadius.circular(12),
							boxShadow: [
								BoxShadow(
									color: Colors.black.withValues(alpha: 0.12),
									blurRadius: 10,
									offset: const Offset(0, 4),
								),
							],
						),
						child: Text(
							label!,
							maxLines: 1,
							overflow: TextOverflow.ellipsis,
							softWrap: false,
							style: const TextStyle(
								fontSize: 12,
								fontWeight: FontWeight.w700,
								color: Colors.deepPurple,
							),
						),
					),
				const SizedBox(height: 6),
				Container(
					width: 42,
					height: 42,
					decoration: BoxDecoration(
						color: Colors.deepPurple,
						borderRadius: BorderRadius.circular(14),
						boxShadow: [
							BoxShadow(
								color: Colors.black.withValues(alpha: 0.2),
								blurRadius: 10,
								offset: const Offset(0, 4),
							),
						],
					),
					child: const Icon(
						Icons.place,
						color: Colors.white,
						size: 22,
					),
				),
			],
		);
	}
}

class _VisitEmptyState extends StatelessWidget {
  const _VisitEmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 48),
      children: const [
        Icon(Icons.inbox_outlined, size: 72, color: Colors.black26),
        SizedBox(height: 16),
        Text(
          'Belum ada data visit tersedia.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.black54),
        ),
      ],
    );
  }
}

class _VisitErrorState extends StatelessWidget {
  const _VisitErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}

class VisitSavingIndicator extends StatelessWidget {
	const VisitSavingIndicator({super.key});

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		return Container(
			width: double.infinity,
			padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
			decoration: BoxDecoration(
				color: Colors.deepPurple.withValues(alpha: 0.08),
				borderRadius: BorderRadius.circular(16),
				border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.18)),
			),
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Row(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Container(
								width: 32,
								height: 32,
								decoration: BoxDecoration(
									color: Colors.deepPurple,
									borderRadius: BorderRadius.circular(12),
								),
								child: const Icon(
									Icons.hourglass_top_outlined,
									size: 18,
									color: Colors.white,
								),
							),
							const SizedBox(width: 12),
							Expanded(
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
										Text(
											'Sedang menyimpan visit',
											style: theme.textTheme.titleSmall?.copyWith(
														fontWeight: FontWeight.w700,
														color: Colors.deepPurple,
													) ??
													const TextStyle(
														fontSize: 15,
														fontWeight: FontWeight.w700,
														color: Colors.deepPurple,
													),
										),
										const SizedBox(height: 4),
										Text(
											'Jangan tutup aplikasi sampai proses selesai.',
											style: theme.textTheme.bodySmall?.copyWith(
														color: Colors.black87,
													) ??
													const TextStyle(
														fontSize: 13,
														color: Colors.black87,
													),
										),
									],
								),
							),
						],
					),
					const SizedBox(height: 14),
					ClipRRect(
						borderRadius: BorderRadius.circular(10),
						child: const LinearProgressIndicator(
							minHeight: 6,
							color: Colors.deepPurple,
							backgroundColor: Colors.white,
						),
					),
				],
			),
		);
	}
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status.toLowerCase().contains('selesai')
        ? Colors.green
        : status.toLowerCase().contains('batal')
        ? Colors.red
        : Colors.deepPurple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OwnerCustomerView extends StatelessWidget {
  const _OwnerCustomerView({required this.customers});

  final List<CustomerData> customers;

  int _countByStatus(String status) =>
      customers.where((customer) => customer.status == status).length;

  @override
  Widget build(BuildContext context) {
    final prospectCount = _countByStatus('Prospek');
    final negotiationCount = _countByStatus('Negosiasi');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ringkasan Customer',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _OwnerSummaryCard(
                title: 'Total Customer',
                value: customers.length.toString(),
                icon: Icons.people_alt_outlined,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _OwnerSummaryCard(
                title: 'Prospek Aktif',
                value: prospectCount.toString(),
                icon: Icons.stacked_line_chart,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _OwnerSummaryCard(
                title: 'Tahap Negosiasi',
                value: negotiationCount.toString(),
                icon: Icons.handshake_outlined,
                color: Colors.teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            itemCount: customers.length,
            separatorBuilder: (context, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final customer = customers[index];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _StatusPill(status: customer.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      customer.category,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.update,
                          size: 16,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Aktivitas terakhir: ${customer.lastActivity}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_outlined,
                          size: 16,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          customer.customerTypeLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OwnerSummaryCard extends StatelessWidget {
  const _OwnerSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _OwnerVisitView extends StatefulWidget {
  const _OwnerVisitView({
    required this.visitItems,
    required this.isLoading,
    required this.errorMessage,
    required this.filterType,
    required this.dateRange,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.authToken,
  });

  final List<VisitData> visitItems;
  final bool isLoading;
  final String? errorMessage;
  final String filterType;
  final DateTimeRange? dateRange;
  final void Function(String filterType, DateTimeRange? dateRange) onFilterChanged;
  final VoidCallback onRefresh;
  final String authToken;

  @override
  State<_OwnerVisitView> createState() => _OwnerVisitViewState();
}

class _OwnerVisitViewState extends State<_OwnerVisitView> {
  late String _currentFilterType;
  DateTimeRange? _currentDateRange;

  @override
  void initState() {
    super.initState();
    _currentFilterType = widget.filterType;
    _currentDateRange = widget.dateRange;
  }

  @override
  void didUpdateWidget(covariant _OwnerVisitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterType != widget.filterType) {
      _currentFilterType = widget.filterType;
    }
    if (oldWidget.dateRange != widget.dateRange) {
      _currentDateRange = widget.dateRange;
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _currentDateRange,
    );
    if (picked != null) {
      setState(() {
        _currentDateRange = picked;
        _currentFilterType = 'custom';
      });
      widget.onFilterChanged('custom', picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Visit',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                DropdownButton<String>(
                  value: _currentFilterType,
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Hari Ini')),
                    DropdownMenuItem(value: 'week', child: Text('Minggu Ini')),
                    DropdownMenuItem(value: 'month', child: Text('Bulan Ini')),
                    DropdownMenuItem(value: 'year', child: Text('Tahun Ini')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      if (value == 'custom') {
                        _selectDateRange();
                      } else {
                        setState(() {
                          _currentFilterType = value;
                          _currentDateRange = null;
                        });
                        widget.onFilterChanged(value, null);
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Total: ${widget.visitItems.length} Visit',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: widget.isLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.errorMessage != null
                  ? Center(
                      child: Text(
                        widget.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : widget.visitItems.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 48),
                          children: const [
                            Icon(Icons.inbox_outlined, size: 72, color: Colors.black26),
                            SizedBox(height: 16),
                            Text(
                              'Belum ada data visit tersedia.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, color: Colors.black54),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Coba ubah filter tanggal untuk melihat data visit lainnya.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.black38),
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: widget.visitItems.length,
                          separatorBuilder: (context, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final visit = widget.visitItems[index];
                            return _VisitCard(visit: visit, authToken: widget.authToken);
                          },
                        ),
        ),
      ],
    );
  }
}

class _OwnerSpkView extends StatefulWidget {
  const _OwnerSpkView({
    required this.spkItems,
    required this.isLoading,
    required this.errorMessage,
    required this.filterType,
    required this.dateRange,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final List<PurchaseOrderData> spkItems;
  final bool isLoading;
  final String? errorMessage;
  final String filterType;
  final DateTimeRange? dateRange;
  final void Function(String filterType, DateTimeRange? dateRange) onFilterChanged;
  final VoidCallback onRefresh;

  @override
  State<_OwnerSpkView> createState() => _OwnerSpkViewState();
}

class _OwnerSpkViewState extends State<_OwnerSpkView> {
  late String _currentFilterType;
  DateTimeRange? _currentDateRange;

  @override
  void initState() {
    super.initState();
    _currentFilterType = widget.filterType;
    _currentDateRange = widget.dateRange;
  }

  @override
  void didUpdateWidget(covariant _OwnerSpkView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterType != widget.filterType) {
      _currentFilterType = widget.filterType;
    }
    if (oldWidget.dateRange != widget.dateRange) {
      _currentDateRange = widget.dateRange;
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _currentDateRange,
    );
    if (picked != null) {
      setState(() {
        _currentDateRange = picked;
        _currentFilterType = 'custom';
      });
      widget.onFilterChanged('custom', picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SPK',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                DropdownButton<String>(
                  value: _currentFilterType,
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Hari Ini')),
                    DropdownMenuItem(value: 'week', child: Text('Minggu Ini')),
                    DropdownMenuItem(value: 'month', child: Text('Bulan Ini')),
                    DropdownMenuItem(value: 'year', child: Text('Tahun Ini')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      if (value == 'custom') {
                        _selectDateRange();
                      } else {
                        setState(() {
                          _currentFilterType = value;
                          _currentDateRange = null;
                        });
                        widget.onFilterChanged(value, null);
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Total: ${widget.spkItems.length} SPK',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: widget.isLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.errorMessage != null
                  ? Center(
                      child: Text(
                        widget.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : widget.spkItems.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 48),
                          children: const [
                            Icon(Icons.assignment_outlined, size: 72, color: Colors.black26),
                            SizedBox(height: 16),
                            Text(
                              'Belum ada data SPK tersedia.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, color: Colors.black54),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Coba ubah filter tanggal untuk melihat data SPK lainnya.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.black38),
                            ),
                          ],
                        )
                      : ListView.separated(
                      itemCount: widget.spkItems.length,
                      separatorBuilder: (context, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final order = widget.spkItems[index];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _SpkDetailSheet.show(context, order),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          order.spkNumber,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (order.status != null)
                                        _buildTag(
                                          order.status!,
                                          backgroundColor: Colors.orange.withValues(alpha: 0.12),
                                          foregroundColor: Colors.orange.shade700,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    order.customerName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Marketing: ${order.userName}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildMetaRow(
                                    icon: Icons.store_outlined,
                                    label: order.dealerName,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMetaRow(
                                    icon: Icons.directions_car_outlined,
                                    label: '${order.merk} ${order.model} • ${order.bodyTypeName}',
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMetaRow(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Jumlah: ${order.quantity} unit',
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMetaRow(
                                    icon: Icons.payments_outlined,
                                    label: order.formattedTotalPrice,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMetaRow(
                                    icon: Icons.calendar_today_outlined,
                                    label: 'Dibuat pada ${order.createdAtLabel}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildTag(
    String text, {
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildMetaRow({required IconData icon, required String label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

class _OwnerUnitMovementView extends StatelessWidget {
  const _OwnerUnitMovementView({required this.unitMovements});

  final List<UnitMovementData> unitMovements;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pergerakan Unit',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: unitMovements.length,
            separatorBuilder: (context, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final movement = unitMovements[index];
              final isOutbound =
                  movement.movementType == UnitMovementType.outbound;
              final color = isOutbound ? Colors.redAccent : Colors.green;
              final label = isOutbound ? 'Unit Keluar' : 'Unit Masuk';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          movement.unitName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _buildTag(
                          label,
                          backgroundColor: color.withValues(alpha: 0.12),
                          foregroundColor: color,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _OwnerMetaRow(
                      icon: Icons.place_outlined,
                      label: movement.location,
                    ),
                    const SizedBox(height: 8),
                    _OwnerMetaRow(
                      icon: Icons.access_time,
                      label: movement.timestamp,
                    ),
                    if (movement.notes != null) ...[
                      const SizedBox(height: 8),
                      _OwnerMetaRow(
                        icon: Icons.notes_outlined,
                        label: movement.notes!,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTag(
    String text, {
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OwnerMetaRow extends StatelessWidget {
  const _OwnerMetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

class _AddPurchaseOrderSheet extends StatefulWidget {
	const _AddPurchaseOrderSheet({
		required this.authToken,
		required this.dealersEndpoint,
		required this.bodyTypesEndpoint,
		required this.onCompleted,
	});

	final String authToken;
	final String dealersEndpoint;
	final String bodyTypesEndpoint;
	final ValueChanged<PurchaseOrderPayload> onCompleted;

	@override
	State<_AddPurchaseOrderSheet> createState() => _AddPurchaseOrderSheetState();
}

class _AddPurchaseOrderSheetState extends State<_AddPurchaseOrderSheet> {
	final _formKey = GlobalKey<FormState>();
	final TextEditingController _customerNameController = TextEditingController();
	final TextEditingController _customerPhoneController = TextEditingController();
	final TextEditingController _customerAddressController = TextEditingController();
	final TextEditingController _merkController = TextEditingController();
	final TextEditingController _chassisNumberController = TextEditingController();
	final TextEditingController _modelController = TextEditingController();
	final TextEditingController _outerLengthController = TextEditingController();
	final TextEditingController _outerHeightController = TextEditingController();
	final TextEditingController _outerWidthController = TextEditingController();
	final TextEditingController _optionalController = TextEditingController();
	final TextEditingController _unitPriceController = TextEditingController();
	final TextEditingController _quantityController = TextEditingController(text: '1');

	List<DealerData> _dealers = const [];
	List<BodyTypeData> _bodyTypes = const [];
	bool _isLoadingDealers = true;
	bool _isLoadingBodyTypes = true;
	DealerData? _selectedDealer;
	BodyTypeData? _selectedBodyType;
	double _totalPrice = 0.0;

	@override
	void initState() {
		super.initState();
		_loadDealers();
		_loadBodyTypes();
		_unitPriceController.addListener(_calculateTotal);
		_quantityController.addListener(_calculateTotal);
	}

	@override
	void dispose() {
		_customerNameController.dispose();
		_customerPhoneController.dispose();
		_customerAddressController.dispose();
		_merkController.dispose();
		_chassisNumberController.dispose();
		_modelController.dispose();
		_outerLengthController.dispose();
		_outerHeightController.dispose();
		_outerWidthController.dispose();
		_optionalController.dispose();
		_unitPriceController.dispose();
		_quantityController.dispose();
		super.dispose();
	}

	Future<void> _loadDealers() async {
		try {
			final response = await http.get(
				Uri.parse(widget.dealersEndpoint),
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 200) {
				final decoded = jsonDecode(response.body) as Map<String, dynamic>;
				if (decoded['success'] == true) {
					final raw = decoded['data'];
					final dealers = raw is List
							? raw
									.map((item) => item is Map<String, dynamic>
											? DealerData.fromJson(item)
											: null)
									.whereType<DealerData>()
									.toList()
							: <DealerData>[];
					if (mounted) {
						setState(() {
							_dealers = dealers;
							_isLoadingDealers = false;
						});
					}
				}
			}
		} catch (error) {
			if (mounted) {
				setState(() {
					_isLoadingDealers = false;
				});
			}
		}
	}

	Future<void> _loadBodyTypes() async {
		try {
			final response = await http.get(
				Uri.parse(widget.bodyTypesEndpoint),
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 200) {
				final decoded = jsonDecode(response.body) as Map<String, dynamic>;
				if (decoded['success'] == true) {
					final raw = decoded['data'];
					final bodyTypes = raw is List
							? raw
									.map((item) => item is Map<String, dynamic>
											? BodyTypeData.fromJson(item)
											: null)
									.whereType<BodyTypeData>()
									.toList()
							: <BodyTypeData>[];
					if (mounted) {
						setState(() {
							_bodyTypes = bodyTypes;
							_isLoadingBodyTypes = false;
						});
					}
				}
			}
		} catch (error) {
			if (mounted) {
				setState(() {
					_isLoadingBodyTypes = false;
				});
			}
		}
	}

	void _calculateTotal() {
		final unitPrice = double.tryParse(_unitPriceController.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
		final quantity = int.tryParse(_quantityController.text) ?? 1;
		setState(() {
			_totalPrice = unitPrice * quantity;
		});
	}

	void _handleSubmit() {
		if (!_formKey.currentState!.validate()) {
			return;
		}

		if (_selectedDealer == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Pilih dealer terlebih dahulu.')),
			);
			return;
		}

		if (_selectedBodyType == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Pilih tipe pengerjaan terlebih dahulu.')),
			);
			return;
		}

		final unitPrice = double.tryParse(_unitPriceController.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
		final quantity = int.tryParse(_quantityController.text) ?? 1;

		final payload = PurchaseOrderPayload(
			dealerId: _selectedDealer!.id,
			customerName: _customerNameController.text.trim(),
			customerPhone: _customerPhoneController.text.trim(),
			customerAddress: _customerAddressController.text.trim(),
			merk: _merkController.text.trim(),
			chassisNumber: _chassisNumberController.text.trim(),
			model: _modelController.text.trim(),
			bodyTypeId: _selectedBodyType!.id,
			outerLength: _outerLengthController.text.trim(),
			outerHeight: _outerHeightController.text.trim(),
			outerWidth: _outerWidthController.text.trim(),
			optional: _optionalController.text.trim().isEmpty ? null : _optionalController.text.trim(),
			unitPrice: unitPrice,
			quantity: quantity,
		);

		widget.onCompleted(payload);
	}

	@override
	Widget build(BuildContext context) {
		final bottomPadding = MediaQuery.of(context).viewInsets.bottom + 24;

		return Padding(
			padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
			child: SingleChildScrollView(
				child: Form(
					key: _formKey,
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Row(
								mainAxisAlignment: MainAxisAlignment.spaceBetween,
								children: [
									const Text(
										'Tambah SPK',
										style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
									),
									IconButton(
										onPressed: () => Navigator.of(context).pop(),
										icon: const Icon(Icons.close),
									),
								],
							),
							const SizedBox(height: 24),
							Autocomplete<DealerData>(
								optionsBuilder: (textEditingValue) {
									if (textEditingValue.text.isEmpty) {
										return _dealers;
									}
									return _dealers.where((dealer) {
										return dealer.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
									});
								},
								displayStringForOption: (dealer) => dealer.name,
								onSelected: (dealer) {
									setState(() {
										_selectedDealer = dealer;
									});
								},
								fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
									if (_selectedDealer != null && controller.text.isEmpty) {
										controller.text = _selectedDealer!.name;
									}
									return TextFormField(
										controller: controller,
										focusNode: focusNode,
										decoration: InputDecoration(
											labelText: 'Dealer',
											hintText: _isLoadingDealers ? 'Memuat dealer...' : 'Cari atau pilih dealer',
											prefixIcon: const Icon(Icons.store_outlined),
											border: OutlineInputBorder(
												borderRadius: BorderRadius.circular(12),
											),
											contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
										),
										enabled: !_isLoadingDealers,
										validator: (value) =>
												_selectedDealer == null ? 'Pilih dealer' : null,
									);
								},
								optionsViewBuilder: (context, onSelected, options) {
									return Align(
										alignment: Alignment.topLeft,
										child: Material(
											elevation: 4.0,
											borderRadius: BorderRadius.circular(12),
											child: ConstrainedBox(
												constraints: const BoxConstraints(maxHeight: 200),
												child: ListView.builder(
													padding: EdgeInsets.zero,
													shrinkWrap: true,
													itemCount: options.length,
													itemBuilder: (context, index) {
														final dealer = options.elementAt(index);
														return ListTile(
															leading: const Icon(Icons.store_outlined, size: 20),
															title: Text(dealer.name),
															onTap: () => onSelected(dealer),
														);
													},
												),
											),
										),
									);
								},
							),
							const SizedBox(height: 16),
							const Text(
								'Informasi Customer',
								style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _customerNameController,
								decoration: InputDecoration(
									labelText: 'Nama Pemesan',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) =>
										value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _customerPhoneController,
								decoration: InputDecoration(
									labelText: 'Nomor Telepon',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								keyboardType: TextInputType.phone,
								validator: (value) =>
										value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _customerAddressController,
								decoration: InputDecoration(
									labelText: 'Alamat Customer',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								maxLines: 2,
								validator: (value) =>
										value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
							),
							const SizedBox(height: 16),
							const Text(
								'Spesifikasi Kendaraan',
								style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _merkController,
								decoration: InputDecoration(
									labelText: 'Merek',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) =>
										value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _chassisNumberController,
								decoration: InputDecoration(
									labelText: 'Nomor Rangka',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) =>
										value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _modelController,
								decoration: InputDecoration(
									labelText: 'Model',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) =>
										value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
							),
							const SizedBox(height: 12),
							Autocomplete<BodyTypeData>(
								optionsBuilder: (textEditingValue) {
									if (textEditingValue.text.isEmpty) {
										return _bodyTypes;
									}
									return _bodyTypes.where((type) {
										return type.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
									});
								},
								displayStringForOption: (type) => type.name,
								onSelected: (type) {
									setState(() {
										_selectedBodyType = type;
									});
								},
								fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
									if (_selectedBodyType != null && controller.text.isEmpty) {
										controller.text = _selectedBodyType!.name;
									}
									return TextFormField(
										controller: controller,
										focusNode: focusNode,
										decoration: InputDecoration(
											labelText: 'Pengerjaan',
											hintText: _isLoadingBodyTypes ? 'Memuat tipe pengerjaan...' : 'Cari atau pilih pengerjaan',
											prefixIcon: const Icon(Icons.build_outlined),
											border: OutlineInputBorder(
												borderRadius: BorderRadius.circular(12),
											),
											contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
										),
										enabled: !_isLoadingBodyTypes,
										validator: (value) =>
												_selectedBodyType == null ? 'Pilih tipe pengerjaan' : null,
									);
								},
								optionsViewBuilder: (context, onSelected, options) {
									return Align(
										alignment: Alignment.topLeft,
										child: Material(
											elevation: 4.0,
											borderRadius: BorderRadius.circular(12),
											child: ConstrainedBox(
												constraints: const BoxConstraints(maxHeight: 200),
												child: ListView.builder(
													padding: EdgeInsets.zero,
													shrinkWrap: true,
													itemCount: options.length,
													itemBuilder: (context, index) {
														final type = options.elementAt(index);
														return ListTile(
															leading: const Icon(Icons.build_outlined, size: 20),
															title: Text(type.name),
															onTap: () => onSelected(type),
														);
													},
												),
											),
										),
									);
								},
							),
							const SizedBox(height: 16),
							const Text(
								'Dimensi Luar',
								style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
							),
							const SizedBox(height: 12),
							Row(
								children: [
									Expanded(
										child: TextFormField(
											controller: _outerLengthController,
											decoration: InputDecoration(
												labelText: 'Panjang',
												border: OutlineInputBorder(
													borderRadius: BorderRadius.circular(12),
												),
											),
											validator: (value) =>
													value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
										),
									),
									const SizedBox(width: 12),
									Expanded(
										child: TextFormField(
											controller: _outerHeightController,
											decoration: InputDecoration(
												labelText: 'Tinggi',
												border: OutlineInputBorder(
													borderRadius: BorderRadius.circular(12),
												),
											),
											validator: (value) =>
													value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
										),
									),
								],
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _outerWidthController,
								decoration: InputDecoration(
									labelText: 'Lebar',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								validator: (value) =>
										value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _optionalController,
								decoration: InputDecoration(
									labelText: 'Opsional (jika ada)',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								maxLines: 2,
							),
							const SizedBox(height: 16),
							const Text(
								'Harga dan Jumlah',
								style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _unitPriceController,
								decoration: InputDecoration(
									labelText: 'Harga per Unit (Rp)',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								keyboardType: TextInputType.number,
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Wajib diisi';
									}
									final price = double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
									if (price == null || price <= 0) {
										return 'Harga harus lebih dari 0';
									}
									return null;
								},
							),
							const SizedBox(height: 12),
							TextFormField(
								controller: _quantityController,
								decoration: InputDecoration(
									labelText: 'Jumlah',
									border: OutlineInputBorder(
										borderRadius: BorderRadius.circular(12),
									),
								),
								keyboardType: TextInputType.number,
								validator: (value) {
									if (value == null || value.trim().isEmpty) {
										return 'Wajib diisi';
									}
									final qty = int.tryParse(value);
									if (qty == null || qty <= 0) {
										return 'Jumlah harus lebih dari 0';
									}
									return null;
								},
							),
							const SizedBox(height: 16),
							Container(
								padding: const EdgeInsets.all(16),
								decoration: BoxDecoration(
									color: Colors.orange.withValues(alpha: 0.08),
									borderRadius: BorderRadius.circular(12),
									border: Border.all(color: Colors.orange.withValues(alpha: 0.18)),
								),
								child: Row(
									mainAxisAlignment: MainAxisAlignment.spaceBetween,
									children: [
										const Text(
											'Total Harga:',
											style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
										),
										Text(
											'Rp ${_totalPrice.toStringAsFixed(0).replaceAllMapped(
														RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
														(match) => '${match[1]}.',
													)}',
											style: const TextStyle(
												fontSize: 18,
												fontWeight: FontWeight.bold,
												color: Colors.orange,
											),
										),
									],
								),
							),
							const SizedBox(height: 24),
							SizedBox(
								width: double.infinity,
								child: FilledButton(
									onPressed: _handleSubmit,
									style: FilledButton.styleFrom(
										backgroundColor: Colors.orange,
										padding: const EdgeInsets.symmetric(vertical: 16),
										shape: RoundedRectangleBorder(
											borderRadius: BorderRadius.circular(12),
										),
									),
									child: const Text(
										'Simpan SPK',
										style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
									),
								),
							),
						],
					),
				),
			),
		);
	}
}

class PurchaseOrderPayload {
	const PurchaseOrderPayload({
		required this.dealerId,
		required this.customerName,
		required this.customerPhone,
		required this.customerAddress,
		required this.merk,
		required this.chassisNumber,
		required this.model,
		required this.bodyTypeId,
		required this.outerLength,
		required this.outerHeight,
		required this.outerWidth,
		this.optional,
		required this.unitPrice,
		required this.quantity,
	});

	final int dealerId;
	final String customerName;
	final String customerPhone;
	final String customerAddress;
	final String merk;
	final String chassisNumber;
	final String model;
	final int bodyTypeId;
	final String outerLength;
	final String outerHeight;
	final String outerWidth;
	final String? optional;
	final double unitPrice;
	final int quantity;
}

class VisitData {
  const VisitData({
    required this.dealerName,
    this.dealerAddress,
    this.visitDateLabel,
    this.latitude,
    this.longitude,
    this.customerName,
		this.customerPhone,
		this.status,
		this.selfieUrl,
		this.selfieThumbnailUrl,
		this.selfieLabel,
		this.selfieTakenAt,
		this.notes,
  });

  final String dealerName;
  final String? dealerAddress;
  final String? visitDateLabel;
  final double? latitude;
  final double? longitude;
  final String? customerName;
	final String? customerPhone;
  final String? status;
	final String? selfieUrl;
	final String? selfieThumbnailUrl;
	final String? selfieLabel;
	final DateTime? selfieTakenAt;
	final String? notes;

  String get displayDealerName =>
      dealerName.trim().isEmpty ? 'Dealer tanpa nama' : dealerName;

  String get dealerAddressLabel =>
      dealerAddress != null && dealerAddress!.trim().isNotEmpty
      ? dealerAddress!
      : 'Alamat dealer belum tersedia';

  String? get coordinateLabel {
    if (latitude == null || longitude == null) return null;
    return '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
  }

	bool get hasSelfie => selfieUrl != null && selfieUrl!.isNotEmpty;

	String get selfieDisplayLabel =>
			selfieLabel != null && selfieLabel!.trim().isNotEmpty
					? selfieLabel!
					: 'Dokumentasi Selfie';

	String? get selfieTakenAtLabel =>
			selfieTakenAt != null ? _formatDateTime(selfieTakenAt!) : null;

	factory VisitData.fromJson(
		Map<String, dynamic> json, {
		String? mediaBaseUrl,
	}) {
    final dealerMap = _findMap(json, [
      'dealer',
      'dealer_data',
      'dealer_detail',
      'dealerInfo',
      'dealer_info',
    ]);

    final locationMap = _findMap(json, [
      'location',
      'coordinate',
      'coordinates',
      'geo',
      'position',
      'visit_location',
    ]);

    final customerMap = _findMap(json, [
      'customer',
      'customer_data',
      'customer_detail',
      'customerInfo',
      'customer_info',
    ]);

		final selfieMap = _findMap(json, [
			'selfie',
			'selfie_data',
			'selfie_media',
			'photo',
			'photo_data',
			'media',
			'visit_selfie',
		]);

    final dealerName =
        _clean(
          _readString(dealerMap, ['name', 'dealer_name', 'title', 'company']) ??
              _readString(json, [
                'dealer_name',
                'dealer',
                'dealerCompany',
                'dealer_title',
              ]),
        ) ??
        'Dealer tanpa nama';

    final dealerAddress = _clean(
      _readString(dealerMap, [
            'address',
            'alamat',
            'dealer_address',
            'location',
            'address1',
            'address_line',
            'street',
          ]) ??
					_readString(json, [
						'dealer_address',
						'address_dealer',
						'alamat_dealer',
						'dealerLocation',
						'dealer',
						'dealerAddress',
					]),
    );

	final customerPhone = _clean(
		_readString(customerMap, [
			'phone',
			'phone_number',
			'telp',
			'telepon',
			'mobile',
			'handphone',
		]) ??
		_readString(json, [
			'customer_phone',
			'phone',
			'phone_number',
			'contact_phone',
		]),
	);

	final status = _clean(
      _readString(json, ['status', 'visit_status', 'state']),
    );

    final createdAt = _readDateTime(json, [
      'created_at',
      'createdAt',
      'visit_created_at',
      'created_on',
      'timestamp',
      'date',
    ]);

    final visitDateLabel = createdAt != null
        ? _formatDateTime(createdAt)
        : null;

    final latitude =
        _readCoordinate(json, [
          'latitude',
          'lat',
          'visit_latitude',
          'latitude_visit',
          'lat_visit',
        ]) ??
        _readCoordinate(locationMap, ['latitude', 'lat', 'y']) ??
        _readCoordinate(dealerMap, ['latitude', 'lat']);

    final longitude =
        _readCoordinate(json, [
          'longitude',
          'lng',
          'long',
          'visit_longitude',
          'longitude_visit',
          'lon_visit',
        ]) ??
        _readCoordinate(locationMap, ['longitude', 'lng', 'x']) ??
        _readCoordinate(dealerMap, ['longitude', 'lng', 'long']);

    final customerName = _clean(
      _readString(customerMap, [
            'name',
            'customer_name',
            'full_name',
            'company_name',
          ]) ??
          _readString(json, [
            'customer_name',
            'customerName',
            'customer',
            'customer_fullname',
          ]),
    );

		final selfieUrlRaw = _clean(
			_readString(json, [
						'selfie_url',
						'selfie',
						'photo_url',
						'photo',
						'image_url',
						'image',
						'media_url',
						'documentation_url',
					]) ??
					_readString(selfieMap, [
						'url',
						'full_url',
						'original_url',
						'secure_url',
						'path',
						'file',
						'source',
						'src',
					]),
		);

		final selfieThumbnailRaw = _clean(
			_readString(json, [
						'selfie_thumbnail',
						'selfie_thumb',
						'photo_thumbnail',
						'thumbnail',
					]) ??
					_readString(selfieMap, [
						'thumbnail_url',
						'thumb_url',
						'preview_url',
						'thumbnail',
						'thumb',
					]),
		);

		DateTime? selfieTakenAt;
		if (selfieMap != null) {
			selfieTakenAt = _readDateTime(selfieMap, [
						'captured_at',
						'taken_at',
						'created_at',
						'timestamp',
						'createdAt',
					]) ??
					selfieTakenAt;
		}
		selfieTakenAt ??= _readDateTime(json, [
			'selfie_captured_at',
			'selfie_taken_at',
			'selfie_created_at',
		]);

		final selfieLabel = _clean(
			_readString(selfieMap, [
						'label',
						'title',
						'name',
						'description',
					]) ??
					_readString(json, [
						'selfie_label',
						'photo_label',
						'documentation_label',
					]),
		);

		final notes = _clean(
			_readString(json, [
				'notes',
				'visit_notes',
				'remark',
				'remarks',
				'keterangan',
				'description',
			]),
		);

		final selfieUrl = _resolveUrl(
			selfieUrlRaw,
			baseUrl: mediaBaseUrl,
		);
		final selfieThumbnailUrl = _resolveUrl(
			selfieThumbnailRaw,
			baseUrl: mediaBaseUrl,
		);

		if (kDebugMode) {
			print('🔧 Raw selfie URLs:');
			print('  selfieUrlRaw: $selfieUrlRaw');
			print('  selfieUrl: $selfieUrl');
			print('  selfieThumbnailUrl: $selfieThumbnailUrl');
		}

		// Fix selfie URLs: if path starts with 'visits/' but doesn't contain '/storage/', add '/storage/'
		String? _fixSelfieUrl(String? url) {
			if (url == null || mediaBaseUrl == null) return url;
			if (!url.startsWith(mediaBaseUrl)) return url;
			final path = url.substring(mediaBaseUrl.length);
			if (path.startsWith('/visits/') && !path.contains('/storage/')) {
				final fixed = url.replaceFirst('/visits/', '/storage/visits/');
				if (kDebugMode) {
					print('🔧 Fixed selfie URL: $url -> $fixed');
				}
				return fixed;
			}
			return url;
		}

		final fixedSelfieUrl = _fixSelfieUrl(selfieUrl);
		final fixedSelfieThumbnailUrl = _fixSelfieUrl(selfieThumbnailUrl);

		return VisitData(
			dealerName: dealerName,
			dealerAddress: dealerAddress,
			visitDateLabel: visitDateLabel,
			latitude: latitude,
			longitude: longitude,
			customerName: customerName,
			customerPhone: customerPhone,
			status: status,
			selfieUrl: fixedSelfieUrl,
			selfieThumbnailUrl: fixedSelfieThumbnailUrl ?? fixedSelfieUrl,
			selfieLabel: selfieLabel,
			selfieTakenAt: selfieTakenAt,
			notes: notes,
		);
  }

  static String? _readString(Map<String, dynamic>? json, List<String> keys) {
    if (json == null) return null;
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      final result = _stringify(json[key]);
      if (result != null && result.isNotEmpty) {
        return result;
      }
    }
    return null;
  }

	static String? _resolveUrl(String? value, {String? baseUrl}) {
		if (value == null) return null;
		final trimmed = value.trim();
		if (trimmed.isEmpty) return null;

		try {
			final directUri = Uri.parse(trimmed);
			if (directUri.hasScheme) {
				return directUri.toString();
			}
		} catch (_) {
			// ignore parse errors and fall back to manual handling
		}

		if (trimmed.startsWith('//')) {
			return 'https:$trimmed';
		}

		if (baseUrl == null || baseUrl.trim().isEmpty) {
			return trimmed;
		}

		final normalizedBase = baseUrl.trim();
		try {
			final baseUri = Uri.parse(normalizedBase);
			final resolved = baseUri.resolve(trimmed);
			return resolved.toString();
		} catch (_) {
			final sanitizedBase = normalizedBase.endsWith('/')
					? normalizedBase.substring(0, normalizedBase.length - 1)
					: normalizedBase;
			if (trimmed.startsWith('/')) {
				return '$sanitizedBase$trimmed';
			}
			return '$sanitizedBase/$trimmed';
		}
	}

  static Map<String, dynamic>? _findMap(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      final map = _castMap(json[key]);
      if (map != null) {
        return map;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _castMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    if (value is String) {
      final trimmed = value.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  static double? _readCoordinate(
    Map<String, dynamic>? json,
    List<String> keys,
  ) {
    if (json == null) return null;
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      final parsed = _toDouble(json[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.replaceAll(',', '.').trim();
      return double.tryParse(normalized);
    }
    return null;
  }

  static DateTime? _readDateTime(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      final parsed = _toDateTime(json[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int || value is double) {
      return _dateTimeFromNumeric(value as num);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final direct = DateTime.tryParse(trimmed);
      if (direct != null) {
        return direct;
      }
      final numeric = double.tryParse(trimmed);
      if (numeric != null) {
        return _dateTimeFromNumeric(numeric);
      }
    }
    return null;
  }

  static DateTime? _dateTimeFromNumeric(num value) {
    if (value <= 0) return null;
    if (value > 1e12) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.round(),
        isUtc: true,
      ).toLocal();
    }
    if (value > 1e9) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.round() * 1000,
        isUtc: true,
      ).toLocal();
    }
    return null;
  }

  static String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final monthName = _monthNames[local.month - 1];
    final datePart =
        '${local.day.toString().padLeft(2, '0')} $monthName ${local.year}';
    final hasTime = local.hour != 0 || local.minute != 0;
    if (!hasTime) {
      return datePart;
    }

    final timePart =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$datePart • $timePart';
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _stringify(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          final decoded = jsonDecode(trimmed);
          final nested = _stringify(decoded);
          if (nested != null && nested.isNotEmpty) {
            return nested;
          }
        } catch (_) {
          // ignore json parse error and fall back to trimmed string
        }
      }
      return trimmed;
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    if (value is DateTime) {
      return _formatDateTime(value);
    }

    if (value is Iterable) {
      final collected = value
          .map(_stringify)
          .whereType<String>()
          .where((element) => element.trim().isNotEmpty)
          .take(3)
          .toList();
      if (collected.isNotEmpty) {
        return collected.join(', ');
      }
      return null;
    }

    final map = _castMap(value);
    if (map != null) {
      for (final key in _preferredNestedKeys) {
        if (!map.containsKey(key)) continue;
        final nested = _stringify(map[key]);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }

      for (final bridgeKey in _bridgeMapKeys) {
        if (!map.containsKey(bridgeKey)) continue;
        final nested = _stringify(map[bridgeKey]);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }

      final collected = <String>[];
      for (final entry in map.entries) {
        final nested = _stringify(entry.value);
        if (nested != null && nested.isNotEmpty) {
          collected.add(nested);
          if (collected.length >= 3) break;
        }
      }

      if (collected.isNotEmpty) {
        return collected.join(' • ');
      }

      return null;
    }

    return value.toString();
  }

  static const List<String> _preferredNestedKeys = [
    'name',
    'full_name',
    'fullName',
    'first_name',
    'last_name',
    'customer_name',
    'title',
    'label',
    'display_name',
    'value',
    'description',
    'text',
    'address',
    'city',
    'company',
    'region',
    'province',
    'district',
    'phone',
    'phone_number',
  ];

  static const List<String> _bridgeMapKeys = [
    'data',
    'attributes',
    'details',
    'meta',
    'value',
    'info',
  ];

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
}

class BodyTypeData {
	const BodyTypeData({
		required this.id,
		required this.name,
	});

	final int id;
	final String name;

	factory BodyTypeData.fromJson(Map<String, dynamic> json) {
		return BodyTypeData(
			id: json['id'] as int? ?? 0,
			name: json['name']?.toString().trim() ?? 
						json['body_type_name']?.toString().trim() ?? 
						'Tipe Tidak Diketahui',
		);
	}
}

class PurchaseOrderData {
	const PurchaseOrderData({
		required this.id,
		this.code,
		this.user,
		required this.dealerName,
		required this.customerName,
		required this.customerPhone,
		required this.customerAddress,
		required this.merk,
		required this.chassisNumber,
		required this.model,
		required this.bodyTypeName,
		required this.outerLength,
		required this.outerHeight,
		required this.outerWidth,
		this.optional,
		required this.unitPrice,
		required this.quantity,
		required this.totalPrice,
		this.status,
		this.createdAt,
		this.progressAt,
		this.completedAt,
	});

	final int id;
	final String? code;
	final Map<String, dynamic>? user;
	final String dealerName;
	final String customerName;
	final String customerPhone;
	final String customerAddress;
	final String merk;
	final String chassisNumber;
	final String model;
	final String bodyTypeName;
	final String outerLength;
	final String outerHeight;
	final String outerWidth;
	final String? optional;
	final double unitPrice;
	final int quantity;
	final double totalPrice;
	final String? status;
	final DateTime? createdAt;
	final DateTime? progressAt;
	final DateTime? completedAt;

	String get spkNumber => code ?? 'SPK-${id.toString().padLeft(3, '0')}';

	String get userName => user?['name']?.toString() ?? 'Marketing Tidak Diketahui';

	String get formattedTotalPrice {
		final formatter = totalPrice.toStringAsFixed(0).replaceAllMapped(
			RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
			(match) => '${match[1]}.',
		);
		return 'Rp $formatter';
	}

	String get createdAtLabel {
		if (createdAt == null) return 'Tanggal tidak tersedia';
		final local = createdAt!.toLocal();
		final monthName = VisitData._monthNames[local.month - 1];
		return '${local.day.toString().padLeft(2, '0')} $monthName ${local.year}';
	}

	String get progressAtLabel {
		if (progressAt == null) return 'Belum ada';
		final local = progressAt!.toLocal();
		final monthName = VisitData._monthNames[local.month - 1];
		return '${local.day.toString().padLeft(2, '0')} $monthName ${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
	}

	String get completedAtLabel {
		if (completedAt == null) return 'Belum ada';
		final local = completedAt!.toLocal();
		final monthName = VisitData._monthNames[local.month - 1];
		return '${local.day.toString().padLeft(2, '0')} $monthName ${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
	}

	factory PurchaseOrderData.fromJson(Map<String, dynamic> json) {
		final dealerData = json['dealer'] as Map<String, dynamic>?;
		final bodyTypeData = json['body_type'] as Map<String, dynamic>?;
		
		final unitPrice = (json['unit_price'] is num) 
			? (json['unit_price'] as num).toDouble() 
			: double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0.0;
		
		final quantity = (json['quantity'] is int)
			? json['quantity'] as int
			: int.tryParse(json['quantity']?.toString() ?? '1') ?? 1;

		final totalPrice = (json['total_price'] is num)
			? (json['total_price'] as num).toDouble()
			: unitPrice * quantity;

		DateTime? createdAt;
		final createdAtRaw = json['created_at'];
		if (createdAtRaw != null) {
			if (createdAtRaw is String) {
				createdAt = DateTime.tryParse(createdAtRaw);
			} else if (createdAtRaw is int) {
				createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtRaw * 1000);
			}
		}

		return PurchaseOrderData(
			id: json['id'] as int? ?? 0,
			code: json['code']?.toString().trim() ?? json['spk_number']?.toString().trim() ?? json['spk_code']?.toString().trim(),
			user: json['user'] as Map<String, dynamic>?,
			dealerName: dealerData?['name']?.toString().trim() ?? 
									dealerData?['dealer_name']?.toString().trim() ?? 
									'Dealer Tidak Diketahui',
			customerName: json['customer_name']?.toString().trim() ?? 'Customer Tidak Diketahui',
			customerPhone: json['customer_phone']?.toString().trim() ?? '-',
			customerAddress: json['customer_address']?.toString().trim() ?? '-',
			merk: json['merk']?.toString().trim() ?? '-',
			chassisNumber: json['chassis_number']?.toString().trim() ?? '-',
			model: json['model']?.toString().trim() ?? '-',
			bodyTypeName: bodyTypeData?['name']?.toString().trim() ?? 
										bodyTypeData?['body_type_name']?.toString().trim() ?? 
										'Tipe Tidak Diketahui',
			outerLength: json['outer_length']?.toString().trim() ?? '-',
			outerHeight: json['outer_height']?.toString().trim() ?? '-',
			outerWidth: json['outer_width']?.toString().trim() ?? '-',
			optional: json['optional']?.toString().trim(),
			unitPrice: unitPrice,
			quantity: quantity,
			totalPrice: totalPrice,
			status: json['status']?.toString().trim(),
			createdAt: createdAt,
			progressAt: (() {
				final raw = json['progressed_at'] ?? json['in_at'] ?? json['progressAt'];
				if (raw == null) return null;
				if (raw is String) return DateTime.tryParse(raw);
				if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
				return null;
			})(),
			completedAt: (() {
				final raw = json['completed_at'] ?? json['out_at'] ?? json['completedAt'];
				if (raw == null) return null;
				if (raw is String) return DateTime.tryParse(raw);
				if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
				return null;
			})(),
		);
	}
}

class _SpkDetailSheet extends StatelessWidget {
	const _SpkDetailSheet({required this.spk});

	final PurchaseOrderData spk;

	static Future<void> show(BuildContext context, PurchaseOrderData spk) {
		return showModalBottomSheet<void>(
			context: context,
			isScrollControlled: true,
			backgroundColor: Colors.transparent,
			builder: (context) => _SpkDetailSheet(spk: spk),
		);
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final statusLabel = spk.status;

		return FractionallySizedBox(
			heightFactor: 0.88,
			child: ClipRRect(
				borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
				child: Material(
					color: Colors.white,
					child: SafeArea(
						top: false,
						child: Column(
							children: [
								const SizedBox(height: 12),
								Container(
									width: 44,
									height: 4,
									decoration: BoxDecoration(
										color: Colors.black26,
										borderRadius: BorderRadius.circular(16),
									),
								),
								Expanded(
									child: SingleChildScrollView(
										padding: EdgeInsets.fromLTRB(
											24,
											24,
											24,
											24 + MediaQuery.of(context).padding.bottom,
										),
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												Text(
													'Detail SPK',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
																color: Colors.orange,
															) ??
															const TextStyle(
																fontSize: 18,
																fontWeight: FontWeight.w700,
																color: Colors.orange,
															),
												),
												const SizedBox(height: 8),
												Text(
													spk.spkNumber,
													style: theme.textTheme.headlineSmall?.copyWith(
																fontSize: 20,
																fontWeight: FontWeight.w700,
																color: Colors.orange.shade700,
															) ??
															const TextStyle(
																fontSize: 20,
																fontWeight: FontWeight.w700,
																color: Colors.orange,
															),
												),
												const SizedBox(height: 18),
												Row(
													crossAxisAlignment: CrossAxisAlignment.start,
													children: [
														Expanded(
															child: Text(
																spk.customerName,
																style: theme.textTheme.headlineSmall?.copyWith(
																			fontSize: 22,
																			fontWeight: FontWeight.w700,
																		) ??
																		const TextStyle(
																			fontSize: 22,
																			fontWeight: FontWeight.w700,
																		),
															),
														),
														if (statusLabel != null && statusLabel.isNotEmpty)
															Padding(
																padding: const EdgeInsets.only(left: 12),
																child: _StatusPill(status: statusLabel),
															),
													],
												),
												const SizedBox(height: 24),
												_VisitDetailItem(
													icon: Icons.store_outlined,
													title: 'Dealer',
													value: spk.dealerName,
												),
												_VisitDetailItem(
													icon: Icons.person_2_outlined,
													title: 'Marketing',
													value: spk.userName,
												),
												_VisitDetailItem(
													icon: Icons.person_outline,
													title: 'Nama Pemesan',
													value: spk.customerName,
												),
												_VisitDetailItem(
													icon: Icons.phone_outlined,
													title: 'Telepon Customer',
													value: spk.customerPhone,
												),
												_VisitDetailItem(
													icon: Icons.location_on_outlined,
													title: 'Alamat Customer',
													value: spk.customerAddress,
												),
												const SizedBox(height: 28),
												Text(
													'Spesifikasi Kendaraan',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
															) ??
															const TextStyle(
																fontSize: 16,
																fontWeight: FontWeight.w700,
															),
												),
												const SizedBox(height: 16),
												_VisitDetailItem(
													icon: Icons.directions_car_outlined,
													title: 'Merek',
													value: spk.merk,
												),
												_VisitDetailItem(
													icon: Icons.confirmation_number_outlined,
													title: 'Nomor Rangka',
													value: spk.chassisNumber,
												),
												_VisitDetailItem(
													icon: Icons.model_training_outlined,
													title: 'Model',
													value: spk.model,
												),
												_VisitDetailItem(
													icon: Icons.build_outlined,
													title: 'Tipe Pengerjaan',
													value: spk.bodyTypeName,
												),
												const SizedBox(height: 28),
												Text(
													'Dimensi Luar',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
															) ??
															const TextStyle(
																fontSize: 16,
																fontWeight: FontWeight.w700,
															),
												),
												const SizedBox(height: 16),
												_VisitDetailItem(
													icon: Icons.straighten_outlined,
													title: 'Panjang',
													value: '${spk.outerLength} cm',
												),
												_VisitDetailItem(
													icon: Icons.height_outlined,
													title: 'Tinggi',
													value: '${spk.outerHeight} cm',
												),
												_VisitDetailItem(
													icon: Icons.swap_horiz_outlined,
													title: 'Lebar',
													value: '${spk.outerWidth} cm',
												),
												if (spk.optional != null && spk.optional!.isNotEmpty) ...[
													const SizedBox(height: 16),
													_VisitDetailItem(
														icon: Icons.note_add_outlined,
														title: 'Opsional',
														value: spk.optional!,
													),
												],
												const SizedBox(height: 28),
												Text(
													'Informasi Harga',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
															) ??
															const TextStyle(
																fontSize: 16,
																fontWeight: FontWeight.w700,
															),
												),
												const SizedBox(height: 16),
												_VisitDetailItem(
													icon: Icons.attach_money_outlined,
													title: 'Harga per Unit',
													value: 'Rp ${spk.unitPrice.toStringAsFixed(0).replaceAllMapped(
														RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
														(match) => '${match[1]}.',
													)}',
												),
												_VisitDetailItem(
													icon: Icons.inventory_2_outlined,
													title: 'Jumlah',
													value: '${spk.quantity} unit',
												),
												_VisitDetailItem(
													icon: Icons.calculate_outlined,
													title: 'Total Harga',
													value: spk.formattedTotalPrice,
												),
												_VisitDetailItem(
													icon: Icons.calendar_today_outlined,
													title: 'Dibuat Pada',
													value: spk.createdAtLabel,
												),
												_VisitDetailItem(
													icon: Icons.login_outlined,
													title: 'Unit Masuk',
													value: spk.progressAtLabel,
												),
												_VisitDetailItem(
													icon: Icons.logout_outlined,
													title: 'Unit Keluar',
													value: spk.completedAtLabel,
												),
											],
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

class SpkData {
  const SpkData({
    required this.number,
    required this.customerName,
    required this.unitName,
    required this.status,
    required this.createdAt,
  });

  final String number;
  final String customerName;
  final String unitName;
  final String status;
  final String createdAt;
}

enum UnitMovementType { inbound, outbound }

class UnitMovementData {
  const UnitMovementData({
    required this.unitName,
    required this.movementType,
    required this.location,
    required this.timestamp,
    this.notes,
  });

  final String unitName;
  final UnitMovementType movementType;
  final String location;
  final String timestamp;
  final String? notes;
}

class CustomerData {
  const CustomerData({
    required this.name,
    required this.category,
    required this.status,
    required this.lastActivity,
    required this.customerTypeLabel,
  });

  final String name;
  final String category;
  final String status;
  final String lastActivity;
  final String customerTypeLabel;
}

class _VisitException implements Exception {
  const _VisitException(this.message);

  final String message;
}

class _UnitMovementSearchSheet extends StatefulWidget {
	const _UnitMovementSearchSheet({
		required this.authToken,
	});

	final String authToken;

	@override
	State<_UnitMovementSearchSheet> createState() => _UnitMovementSearchSheetState();
}

class _UnitMovementSearchSheetState extends State<_UnitMovementSearchSheet> {
	final TextEditingController _searchController = TextEditingController();
	List<PurchaseOrderData> _orders = const [];
	List<PurchaseOrderData> _filteredOrders = const [];
	bool _isLoading = true;
	String? _errorMessage;

	@override
	void initState() {
		super.initState();
		_searchController.addListener(_applyFilter);
		_loadOrders();
	}

	@override
	void dispose() {
		_searchController
			..removeListener(_applyFilter)
			..dispose();
		super.dispose();
	}

	Future<void> _loadOrders() async {
		setState(() {
			_isLoading = true;
			_errorMessage = null;
		});

		try {
			final response = await http.get(
				Uri.parse('${ApiConfig.baseUrl}/api/v1/purchase-orders?status[]=approved&status[]=in_progress'),
				headers: {
					'Accept': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				setState(() {
					_isLoading = false;
				});
				_handleUnauthorized();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				final raw = decoded['data'];
				final orders = raw is List
						? raw
								.map((item) => item is Map<String, dynamic>
										? PurchaseOrderData.fromJson(item)
										: null)
								.whereType<PurchaseOrderData>()
								.toList()
						: <PurchaseOrderData>[];
				setState(() {
					_orders = orders;
					_filteredOrders = orders;
					_isLoading = false;
				});
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal memuat data SPK.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			setState(() {
				_errorMessage = error.message;
				_isLoading = false;
			});
		} on FormatException {
			setState(() {
				_errorMessage = 'Format data SPK tidak valid.';
				_isLoading = false;
			});
		} catch (error) {
			setState(() {
				_errorMessage = 'Terjadi kesalahan: ${error.toString()}';
				_isLoading = false;
			});
		}
	}

	void _applyFilter() {
		final query = _searchController.text.trim().toLowerCase();
		if (query.isEmpty) {
			setState(() {
				_filteredOrders = _orders;
			});
			return;
		}

		setState(() {
			_filteredOrders = _orders
					.where(
						(order) =>
								order.customerName.toLowerCase().contains(query) ||
								order.dealerName.toLowerCase().contains(query) ||
								order.merk.toLowerCase().contains(query) ||
								order.model.toLowerCase().contains(query) ||
								order.chassisNumber.toLowerCase().contains(query),
					)
					.toList();
		});
	}

	void _handleUnauthorized() {
		if (!mounted) return;
		final messenger = ScaffoldMessenger.of(context);
		messenger
			..hideCurrentSnackBar()
			..showSnackBar(
				const SnackBar(
					content: Text('Sesi login berakhir. Silakan login kembali.'),
				),
			);
		_logout(context);
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final bottomPadding = MediaQuery.of(context).padding.bottom + 24;

		return FractionallySizedBox(
			heightFactor: 0.9,
			child: Padding(
				padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
				child: Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						Row(
							mainAxisAlignment: MainAxisAlignment.spaceBetween,
							children: [
								Expanded(
									child: Text(
										'Pilih SPK untuk Unit Movement',
										style: theme.textTheme.titleMedium?.copyWith(
													fontWeight: FontWeight.w700,
												) ??
												const TextStyle(
													fontSize: 18,
													fontWeight: FontWeight.w700,
												),
									),
								),
								IconButton(
									icon: const Icon(Icons.close),
									onPressed: () => Navigator.of(context).pop(),
								),
							],
						),
						const SizedBox(height: 8),
						Text(
							'Cari dan pilih SPK yang sudah approved atau in progress.',
							style: theme.textTheme.bodyMedium?.copyWith(
										color: Colors.black54,
									) ??
									const TextStyle(
										fontSize: 14,
										color: Colors.black54,
									),
						),
						const SizedBox(height: 16),
						TextField(
							controller: _searchController,
							decoration: InputDecoration(
								hintText: 'Cari nama customer, dealer, merk, model...',
								prefixIcon: const Icon(Icons.search),
								border: OutlineInputBorder(
									borderRadius: BorderRadius.circular(14),
								),
								filled: true,
								fillColor: Colors.grey.shade100,
							),
						),
						const SizedBox(height: 16),
						Expanded(
							child: _isLoading
									? const Center(child: CircularProgressIndicator())
									: _errorMessage != null
											? _DealerErrorState(
													message: _errorMessage!,
													onRetry: _loadOrders,
												)
											: _filteredOrders.isEmpty
													? const _DealerEmptyState()
													: RefreshIndicator(
															onRefresh: _loadOrders,
															child: ListView.separated(
																itemCount: _filteredOrders.length,
																separatorBuilder: (context, _) =>
																		const SizedBox(height: 12),
																itemBuilder: (context, index) {
																	final order = _filteredOrders[index];
																	return _SpkTile(
																		order: order,
																		onTap: () =>
																				Navigator.of(context).pop(order),
																	);
																},
															),
														),
						),
					],
				),
			),
		);
	}
}

class _SpkTile extends StatelessWidget {
	const _SpkTile({
		required this.order,
		required this.onTap,
	});

	final PurchaseOrderData order;
	final VoidCallback onTap;

	@override
	Widget build(BuildContext context) {
		return Material(
			color: Colors.white,
			borderRadius: BorderRadius.circular(18),
			child: InkWell(
				borderRadius: BorderRadius.circular(18),
				onTap: onTap,
				child: Padding(
					padding: const EdgeInsets.all(18),
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Row(
								mainAxisAlignment: MainAxisAlignment.spaceBetween,
								children: [
									Expanded(
										child: Text(
											order.spkNumber,
											style: const TextStyle(
												fontSize: 16,
												fontWeight: FontWeight.w700,
											),
										),
									),
									if (order.status != null)
										_StatusPill(status: order.status!),
								],
							),
							const SizedBox(height: 8),
							Text(
								order.customerName,
								style: const TextStyle(
									fontSize: 14,
									color: Colors.black87,
								),
							),
							const SizedBox(height: 4),
							Text(
								'${order.merk} ${order.model} • ${order.bodyTypeName}',
								style: const TextStyle(
									fontSize: 14,
									color: Colors.black87,
								),
							),
							const SizedBox(height: 4),
							Text(
								'Dealer: ${order.dealerName}',
								style: const TextStyle(
									fontSize: 13,
									color: Colors.black54,
								),
							),
							const SizedBox(height: 4),
							Text(
								'Marketing: ${order.userName}',
								style: const TextStyle(
									fontSize: 13,
									color: Colors.black54,
								),
							),
							const SizedBox(height: 4),
							Text(
								'Jumlah: ${order.quantity} unit • ${order.formattedTotalPrice}',
								style: const TextStyle(
									fontSize: 13,
									color: Colors.black54,
								),
							),
						],
					),
				),
			),
		);
	}
}

class _UnitMovementDetailSheet extends StatefulWidget {
	const _UnitMovementDetailSheet({
		required this.order,
		required this.authToken,
		this.onMovementSuccess,
	});

	final PurchaseOrderData order;
	final String authToken;
	final VoidCallback? onMovementSuccess;

	static Future<void> show(BuildContext context, PurchaseOrderData order, String authToken, {VoidCallback? onMovementSuccess}) {
		return showModalBottomSheet<void>(
			context: context,
			isScrollControlled: true,
			backgroundColor: Colors.transparent,
			builder: (context) => _UnitMovementDetailSheet(order: order, authToken: authToken, onMovementSuccess: onMovementSuccess),
		);
	}

	@override
	State<_UnitMovementDetailSheet> createState() => _UnitMovementDetailSheetState();
}

class _UnitMovementDetailSheetState extends State<_UnitMovementDetailSheet> {
	bool _isProcessing = false;

	Future<void> _handleSessionExpired([String? message]) async {
		if (!mounted) return;
		final messenger = ScaffoldMessenger.of(context);
		messenger
			..hideCurrentSnackBar()
			..showSnackBar(
				SnackBar(
					content: Text(
						message ?? 'Sesi login berakhir. Silakan login kembali.',
					),
				),
			);
		await _logout(context);
	}

	Future<void> _handleMovement(String type) async {
		if (_isProcessing) return;

		setState(() {
			_isProcessing = true;
		});

		try {
			// Determine new status based on current status
			final currentStatus = widget.order.status;
			String newStatus;
			if (currentStatus == 'approved') {
				newStatus = 'in_progress';
			} else if (currentStatus == 'in_progress') {
				newStatus = 'completed';
			} else {
				throw _VisitException('Status SPK tidak valid untuk pergerakan unit.');
			}

			// Make API call to update status
			final response = await http.patch(
				Uri.parse('${ApiConfig.baseUrl}/api/v1/purchase-orders/${widget.order.id}/status'),
				headers: {
					'Accept': 'application/json',
					'Content-Type': 'application/json',
					'Authorization': 'Bearer ${widget.authToken}',
				},
				body: jsonEncode({'status': newStatus}),
			);

			if (response.statusCode == 401) {
				if (!mounted) return;
				await _handleSessionExpired();
				return;
			}

			final decoded = jsonDecode(response.body) as Map<String, dynamic>;
			if (response.statusCode >= 200 &&
					response.statusCode < 300 &&
					decoded['success'] == true) {
				if (!mounted) return;
				ScaffoldMessenger.of(context).showSnackBar(
					SnackBar(content: Text('Unit berhasil ${type == 'in' ? 'masuk' : 'keluar'}')),
				);
				// Call the callback to refresh the list
				widget.onMovementSuccess?.call();
				Navigator.of(context).pop();
			} else {
				final message =
						decoded['message']?.toString() ?? 'Gagal memperbarui status unit.';
				throw _VisitException(message);
			}
		} on _VisitException catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text(error.message)),
			);
		} catch (error) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Terjadi kesalahan: $error')),
			);
		} finally {
			if (mounted) {
				setState(() {
					_isProcessing = false;
				});
			}
		}
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final statusLabel = widget.order.status;
		final canMoveIn = statusLabel == 'approved';
		final canMoveOut = statusLabel == 'in_progress';

		return FractionallySizedBox(
			heightFactor: 0.88,
			child: ClipRRect(
				borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
				child: Material(
					color: Colors.white,
					child: SafeArea(
						top: false,
						child: Column(
							children: [
								const SizedBox(height: 12),
								Container(
									width: 44,
									height: 4,
									decoration: BoxDecoration(
										color: Colors.black26,
										borderRadius: BorderRadius.circular(16),
									),
								),
								Expanded(
									child: SingleChildScrollView(
										padding: EdgeInsets.fromLTRB(
											24,
											24,
											24,
											24 + MediaQuery.of(context).padding.bottom,
										),
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												Text(
													'Detail Unit Movement',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
																color: Colors.teal,
															) ??
															const TextStyle(
																fontSize: 18,
																fontWeight: FontWeight.w700,
																color: Colors.teal,
															),
												),
												const SizedBox(height: 8),
												Text(
													widget.order.spkNumber,
													style: theme.textTheme.headlineSmall?.copyWith(
																fontSize: 20,
																fontWeight: FontWeight.w700,
																color: Colors.teal.shade700,
															) ??
															const TextStyle(
																fontSize: 20,
																fontWeight: FontWeight.w700,
																color: Colors.teal,
															),
												),
												const SizedBox(height: 18),
												Row(
													crossAxisAlignment: CrossAxisAlignment.start,
													children: [
														Expanded(
															child: Text(
																widget.order.customerName,
																style: theme.textTheme.headlineSmall?.copyWith(
																			fontSize: 22,
																			fontWeight: FontWeight.w700,
																		) ??
																		const TextStyle(
																			fontSize: 22,
																			fontWeight: FontWeight.w700,
																		),
															),
														),
														if (statusLabel != null && statusLabel.isNotEmpty)
															Padding(
																padding: const EdgeInsets.only(left: 12),
																child: _StatusPill(status: statusLabel),
															),
													],
												),
												const SizedBox(height: 24),
												_VisitDetailItem(
													icon: Icons.store_outlined,
													title: 'Dealer',
													value: widget.order.dealerName,
												),
												_VisitDetailItem(
													icon: Icons.person_2_outlined,
													title: 'Marketing',
													value: widget.order.userName,
												),
												_VisitDetailItem(
													icon: Icons.person_outline,
													title: 'Nama Pemesan',
													value: widget.order.customerName,
												),
												_VisitDetailItem(
													icon: Icons.phone_outlined,
													title: 'Telepon Customer',
													value: widget.order.customerPhone,
												),
												_VisitDetailItem(
													icon: Icons.location_on_outlined,
													title: 'Alamat Customer',
													value: widget.order.customerAddress,
												),
												const SizedBox(height: 28),
												Text(
													'Spesifikasi Kendaraan',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
															) ??
															const TextStyle(
																fontSize: 16,
																fontWeight: FontWeight.w700,
															),
												),
												const SizedBox(height: 16),
												_VisitDetailItem(
													icon: Icons.directions_car_outlined,
													title: 'Merek',
													value: widget.order.merk,
												),
												_VisitDetailItem(
													icon: Icons.confirmation_number_outlined,
													title: 'Nomor Rangka',
													value: widget.order.chassisNumber,
												),
												_VisitDetailItem(
													icon: Icons.model_training_outlined,
													title: 'Model',
													value: widget.order.model,
												),
												_VisitDetailItem(
													icon: Icons.build_outlined,
													title: 'Tipe Pengerjaan',
													value: widget.order.bodyTypeName,
												),
												const SizedBox(height: 28),
												Text(
													'Dimensi Luar',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
															) ??
															const TextStyle(
																fontSize: 16,
																fontWeight: FontWeight.w700,
															),
												),
												const SizedBox(height: 16),
												_VisitDetailItem(
													icon: Icons.straighten_outlined,
													title: 'Panjang',
													value: '${widget.order.outerLength} cm',
												),
												_VisitDetailItem(
													icon: Icons.height_outlined,
													title: 'Tinggi',
													value: '${widget.order.outerHeight} cm',
												),
												_VisitDetailItem(
													icon: Icons.swap_horiz_outlined,
													title: 'Lebar',
													value: '${widget.order.outerWidth} cm',
												),
												if (widget.order.optional != null && widget.order.optional!.isNotEmpty) ...[
													const SizedBox(height: 16),
													_VisitDetailItem(
														icon: Icons.note_add_outlined,
														title: 'Opsional',
														value: widget.order.optional!,
													),
												],
												const SizedBox(height: 28),
												Text(
													'Informasi Harga',
													style: theme.textTheme.titleMedium?.copyWith(
																fontWeight: FontWeight.w700,
															) ??
															const TextStyle(
																fontSize: 16,
																fontWeight: FontWeight.w700,
															),
												),
												const SizedBox(height: 16),
												_VisitDetailItem(
													icon: Icons.attach_money_outlined,
													title: 'Harga per Unit',
													value: 'Rp ${widget.order.unitPrice.toStringAsFixed(0).replaceAllMapped(
														RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
														(match) => '${match[1]}.',
													)}',
												),
												_VisitDetailItem(
													icon: Icons.inventory_2_outlined,
													title: 'Jumlah',
													value: '${widget.order.quantity} unit',
												),
												_VisitDetailItem(
													icon: Icons.calculate_outlined,
													title: 'Total Harga',
													value: widget.order.formattedTotalPrice,
												),
												_VisitDetailItem(
													icon: Icons.calendar_today_outlined,
													title: 'Dibuat Pada',
													value: widget.order.createdAtLabel,
												),
												const SizedBox(height: 32),
												if (canMoveIn || canMoveOut) ...[
													Text(
														'Aksi Unit Movement',
														style: theme.textTheme.titleMedium?.copyWith(
																	fontWeight: FontWeight.w700,
																) ??
																const TextStyle(
																	fontSize: 16,
																	fontWeight: FontWeight.w700,
																),
													),
													const SizedBox(height: 16),
													Row(
														children: [
															if (canMoveIn) ...[
																Expanded(
																	child: FilledButton.icon(
																		onPressed: _isProcessing ? null : () => _handleMovement('in'),
																		icon: const Icon(Icons.move_to_inbox_outlined),
																		label: const Text('IN'),
																		style: FilledButton.styleFrom(
																			backgroundColor: Colors.green,
																			padding: const EdgeInsets.symmetric(vertical: 16),
																		),
																	),
																),
																if (canMoveOut) const SizedBox(width: 12),
															],
															if (canMoveOut) ...[
																Expanded(
																	child: FilledButton.icon(
																		onPressed: _isProcessing ? null : () => _handleMovement('out'),
																		icon: const Icon(Icons.outbox_outlined),
																		label: const Text('OUT'),
																		style: FilledButton.styleFrom(
																			backgroundColor: Colors.redAccent,
																			padding: const EdgeInsets.symmetric(vertical: 16),
																		),
																	),
																),
															],
														],
													),
												],
											],
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
