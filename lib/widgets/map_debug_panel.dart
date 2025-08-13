import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Debug panel widget
class MapDebugPanel extends StatefulWidget {
  final Map<String, dynamic> debugData;
  final VoidCallback onClose;
  final VoidCallback? onSimulateNotification;
  final VoidCallback? onGenerateDummyExperiment;
  final VoidCallback? onClearExperiments;

  const MapDebugPanel({
    Key? key,
    required this.debugData,
    required this.onClose,
    this.onSimulateNotification,
    this.onGenerateDummyExperiment,
    this.onClearExperiments,
  }) : super(key: key);

  @override
  _MapDebugPanelState createState() => _MapDebugPanelState();
}

class _MapDebugPanelState extends State<MapDebugPanel> with TickerProviderStateMixin {
  bool _expanded = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 140,
      left: 8,
      right: 8,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade400, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDebugHeader(),
            if (_expanded) _buildTabbedContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugHeader() {
    final experimentsData = widget.debugData['experiments'] as Map<String, dynamic>? ?? {};
    final totalExperiments = experimentsData['total_experiments'] ?? 0;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade800,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: _expanded ? Radius.zero : Radius.circular(14),
          bottomRight: _expanded ? Radius.zero : Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.bug_report_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'DEBUG PANEL',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                    if (totalExperiments > 0) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade600,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$totalExperiments',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Real-time system monitoring & A* experiments',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green.shade100,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabbedContent() {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              border: Border(bottom: BorderSide(color: Colors.green.shade700.withOpacity(0.3))),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.green.shade400,
              indicatorWeight: 3,
              labelColor: Colors.green.shade300,
              unselectedLabelColor: Colors.grey.shade500,
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              tabs: [
                Tab(icon: Icon(Icons.info_outline, size: 16), text: 'System'),
                Tab(icon: Icon(Icons.science_rounded, size: 16), text: 'A* Tests'),
                Tab(icon: Icon(Icons.speed_rounded, size: 16), text: 'Performance'),
              ],
            ),
          ),
          Flexible(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSystemTab(),
                _buildExperimentsTab(),
                _buildPerformanceTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemTab() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDebugActions(),
          SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDebugSection('SYSTEM', widget.debugData['system']),
                  _buildDebugSection('LOCATION', widget.debugData['location']),
                  _buildDebugSection('USERS', widget.debugData['users']),
                  _buildDebugSection('ROUTING', widget.debugData['routing']),
                  _buildDebugSection('NOTIFICATIONS', widget.debugData['notifications']),
                  _buildDebugSection('UI STATE', widget.debugData['ui_state']),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperimentsTab() {
    final experimentsData = widget.debugData['experiments'] as Map<String, dynamic>? ?? {};
    final totalExperiments = experimentsData['total_experiments'] ?? 0;
    final latestExperiments = experimentsData['latest_experiments'] as List? ?? [];
    final statistics = experimentsData['statistics'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildExperimentActions(),
          SizedBox(height: 16),
          if (statistics.isNotEmpty) ...[
            _buildStatisticsSummary(statistics, totalExperiments),
            SizedBox(height: 16),
          ],
          if (latestExperiments.isNotEmpty) ...[
            _buildExperimentsHeader(latestExperiments.length),
            SizedBox(height: 12),
            Flexible(child: _buildExperimentsList(latestExperiments)),
          ] else ...[
            _buildNoExperimentsState(),
          ],
        ],
      ),
    );
  }

  Widget _buildPerformanceTab() {
    final performanceData = widget.debugData['performance'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPerformanceHeader(),
          SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDebugSection('ROUTING CACHE', widget.debugData['routing']),
                  _buildDebugSection('MEMORY USAGE', performanceData),
                  _buildDebugSection('NETWORK STATUS', widget.debugData['network'] ?? {}),
                  _buildDebugSection('FIREBASE CONNECTIONS', widget.debugData['firebase'] ?? {}),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugActions() {
    return Row(
      children: [
        Expanded(
          child: _buildDebugActionButton(
            icon: Icons.copy_rounded,
            label: 'Copy',
            color: Colors.blue.shade600,
            onTap: () {
              final jsonString = JsonEncoder.withIndent('  ').convert(widget.debugData);
              Clipboard.setData(ClipboardData(text: jsonString));
              _showSnackBar('Debug data copied!', Colors.green);
            },
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _buildDebugActionButton(
            icon: Icons.file_download_rounded,
            label: 'Export',
            color: Colors.purple.shade600,
            onTap: () {
              print('🔥🔥 FULL DEBUG LOG:');
              print(JsonEncoder.withIndent('  ').convert(widget.debugData));
              _showSnackBar('Debug log exported to console', Colors.purple);
            },
          ),
        ),
        if (widget.onSimulateNotification != null) ...[
          SizedBox(width: 8),
          Expanded(
            child: _buildDebugActionButton(
              icon: Icons.notifications_active_rounded,
              label: 'Test',
              color: Colors.red.shade600,
              onTap: widget.onSimulateNotification!,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExperimentActions() {
    return Row(
      children: [
        Expanded(
          child: _buildDebugActionButton(
            icon: Icons.science_rounded,
            label: 'Generate',
            color: Colors.green.shade600,
            onTap: widget.onGenerateDummyExperiment ?? () {},
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _buildDebugActionButton(
            icon: Icons.clear_all_rounded,
            label: 'Clear',
            color: Colors.red.shade600,
            onTap: widget.onClearExperiments ?? () {},
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _buildDebugActionButton(
            icon: Icons.download_rounded,
            label: 'CSV',
            color: Colors.orange.shade600,
            onTap: () => _showSnackBar('CSV export feature coming soon', Colors.orange),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade800.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade600.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.speed_rounded, color: Colors.blue.shade400, size: 18),
          SizedBox(width: 8),
          Text(
            'SYSTEM PERFORMANCE MONITORING',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade300,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSummary(Map<String, dynamic> statistics, int totalExperiments) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade900.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade600.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: Colors.green.shade400, size: 16),
              SizedBox(width: 8),
              Text(
                'A* ALGORITHM STATISTICS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade300,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatItem('Success Rate', statistics['success_rate']?.toString() ?? '0%', Colors.green.shade400)),
              Expanded(child: _buildStatItem('Avg Time', statistics['avg_execution_time']?.toString() ?? '0ms', Colors.blue.shade400)),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatItem('Avg Nodes', statistics['avg_nodes_processed']?.toString() ?? '0', Colors.orange.shade400)),
              Expanded(child: _buildStatItem('Total Tests', '$totalExperiments', Colors.purple.shade400)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
        SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildExperimentsHeader(int count) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade800.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.shade600.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: Colors.orange.shade400, size: 14),
          SizedBox(width: 6),
          Text(
            'LATEST EXPERIMENTS ($count)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade300,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperimentsList(List experiments) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700.withOpacity(0.3)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: experiments.length,
        itemBuilder: (context, index) {
          final experiment = experiments[index] as Map<String, dynamic>;
          return _buildExperimentCard(experiment);
        },
      ),
    );
  }

  Widget _buildExperimentCard(Map<String, dynamic> experiment) {
    final isSuccess = experiment['keterangan']?.toString().contains('ditemukan') ?? false;
    final statusColor = isSuccess ? Colors.green.shade400 : Colors.red.shade400;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green.shade900.withOpacity(0.2) : Colors.red.shade900.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${experiment['no_percobaan']}',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  experiment['keterangan']?.toString() ?? 'Unknown',
                  style: TextStyle(fontSize: 9, color: statusColor, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${experiment['waktu_eksekusi_ms']}ms',
                style: TextStyle(fontSize: 8, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExperimentDataItem('Distance', '${experiment['jarak_garis_lurus_m']}m', Colors.blue.shade400),
                    SizedBox(height: 4),
                    _buildExperimentDataItem('Road Dist', '${experiment['jarak_tempuh_jalan_m']}m', Colors.green.shade400),
                    SizedBox(height: 4),
                    _buildExperimentDataItem('Total Cost', experiment['total_biaya_f']?.toString() ?? '-', Colors.purple.shade400),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExperimentDataItem('Nodes', experiment['jumlah_node_diproses']?.toString() ?? '-', Colors.orange.shade400),
                    SizedBox(height: 4),
                    _buildExperimentDataItem('Route Len', '${experiment['panjang_rute_meter']}m', Colors.cyan.shade400),
                    SizedBox(height: 4),
                    _buildExperimentDataItem('Status', isSuccess ? '✓' : '✗', statusColor),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExperimentDataItem(String label, String value, Color color) {
    return Row(
      children: [
        Text('$label: ', style: TextStyle(fontSize: 8, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildNoExperimentsState() {
    return Container(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.science_outlined, size: 32, color: Colors.grey.shade400),
          ),
          SizedBox(height: 16),
          Text(
            'No A* Experiments Yet',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'Use "Generate" button to create test data\nor trigger routing to record real experiments',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDebugActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugSection(String title, dynamic data) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade800,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade700.withOpacity(0.3)),
            ),
            child: Text(
              _formatDebugData(data),
              style: TextStyle(
                fontSize: 10,
                color: Colors.green.shade300,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDebugData(dynamic data) {
    if (data == null) return 'null';

    if (data is Map) {
      final buffer = StringBuffer();
      data.forEach((key, value) {
        if (value is Map || value is List) {
          buffer.writeln('$key: ${_formatDebugData(value)}');
        } else {
          buffer.writeln('$key: $value');
        }
      });
      return buffer.toString().trim();
    } else if (data is List) {
      if (data.isEmpty) return '[]';
      final buffer = StringBuffer();
      for (int i = 0; i < data.length; i++) {
        buffer.writeln('[$i]: ${_formatDebugData(data[i])}');
      }
      return buffer.toString().trim();
    } else {
      return data.toString();
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green ? Icons.check_circle : Icons.info,
              color: Colors.white,
              size: 16,
            ),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: EdgeInsets.all(16),
      ),
    );
  }
}