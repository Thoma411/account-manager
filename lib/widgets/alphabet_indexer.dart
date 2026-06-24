/*
 * @Author: Thoma4
 * @Date: 2026-06-24 00:55:11
 * @LastEditTime: 2026-06-24 01:21:09
 * @Description: 构建字母索引导航栏
 */

import 'package:flutter/material.dart';

class AlphabetIndexer extends StatelessWidget {
  final Map<String, int> alphabetIndexMap;
  final ValueChanged<String> onLetterSelected;
  final bool alignRight;

  const AlphabetIndexer({
    super.key,
    required this.alphabetIndexMap,
    required this.onLetterSelected,
    this.alignRight = false, // 默认电脑模式居左
  });

  @override
  Widget build(BuildContext context) {
    const List<String> alphabet = [
      '#',
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
    ];
    return Container(
      width: 25, // 宽度
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: alphabet.map((char) {
          bool hasData = alphabetIndexMap.containsKey(char);
          return Expanded(
            child: InkWell(
              onTap: !hasData ? null : () => onLetterSelected(char),
              child: Center(
                child: Text(
                  char,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasData
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
