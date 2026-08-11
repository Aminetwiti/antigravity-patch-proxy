import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class AppearanceSettingsSection extends StatefulWidget {
  const AppearanceSettingsSection({super.key});

  @override
  State<AppearanceSettingsSection> createState() => _AppearanceSettingsSectionState();
}

class _AppearanceSettingsSectionState extends State<AppearanceSettingsSection> {
  int _themeModeIndex = 0; // 0: system, 1: light, 2: dark

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appearance',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.inkPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderStrong),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Appearance',
                      style: TextStyle(fontSize: 13, color: AppColors.inkPrimary, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Select light, dark, or inherit system settings.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              // Theme Mode Toggle
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleBtn(0, Icons.monitor_outlined),
                    _buildToggleBtn(1, Icons.light_mode_outlined),
                    _buildToggleBtn(2, Icons.dark_mode_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text(
          'Light Theme',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.inkPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Column(
            children: [
              _buildSettingRow(
                'Preset',
                _buildDropdownControl('Default Light'),
              ),
              const Divider(color: AppColors.borderSubtle, height: 1, thickness: 1),
              _buildSettingRow(
                'Background',
                _buildColorControl(const Color(0xFFEEEEEE), 'EEEEEE'),
              ),
              const Divider(color: AppColors.borderSubtle, height: 1, thickness: 1),
              _buildSettingRow(
                'Foreground',
                _buildColorControl(const Color(0xFF101010), '101010'),
              ),
              const Divider(color: AppColors.borderSubtle, height: 1, thickness: 1),
              _buildSettingRow(
                'Accent',
                _buildColorControl(const Color(0xFF007ACC), '007ACC'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text(
          'Dark Theme',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.inkPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Column(
            children: [
              _buildSettingRow(
                'Preset',
                _buildDropdownControl('Default Dark'),
              ),
              const Divider(color: AppColors.borderSubtle, height: 1, thickness: 1),
              _buildSettingRow(
                'Background',
                _buildColorControl(const Color(0xFF101010), '101010'),
              ),
              const Divider(color: AppColors.borderSubtle, height: 1, thickness: 1),
              _buildSettingRow(
                'Foreground',
                _buildColorControl(const Color(0xFFCCCCCC), 'CCCCCC'),
              ),
              const Divider(color: AppColors.borderSubtle, height: 1, thickness: 1),
              _buildSettingRow(
                'Accent',
                _buildColorControl(const Color(0xFF007ACC), '007ACC'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleBtn(int index, IconData icon) {
    final isSelected = _themeModeIndex == index;
    return InkWell(
      onTap: () => setState(() => _themeModeIndex = index),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceInput : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected ? AppColors.inkPrimary : AppColors.inkSecondary,
        ),
      ),
    );
  }

  Widget _buildSettingRow(String label, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
          ),
          control,
        ],
      ),
    );
  }

  Widget _buildDropdownControl(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.inkMuted),
        ],
      ),
    );
  }

  Widget _buildColorControl(Color color, String hex) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised, // Using a slightly darker/raised color for the input
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.white.withAlpha(25)),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '# ',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          Text(
            hex,
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkPrimary),
          ),
        ],
      ),
    );
  }
}
