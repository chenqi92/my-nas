/// 类型和地区的多语言映射工具
///
/// 用于将不同语言的类型/地区名称统一映射，支持双向查找
/// 例如：action <-> 动作，USA <-> 美国
class GenreCountryMapping {
  GenreCountryMapping._();

  // ==================== 电影/电视剧类型映射 ====================

  /// 类型同义词组：每组的第一个元素是规范键，后面是同义词和中文
  /// 所有变体（包括中文）都会映射到规范键
  static const List<List<String>> _genreSynonymGroups = [
    // 主要类型
    ['action', '动作'],
    ['adventure', '冒险'],
    ['animation', '动画'],
    ['comedy', '喜剧'],
    ['crime', '犯罪'],
    ['documentary', '纪录片'],
    ['drama', '剧情'],
    ['family', '家庭'],
    ['fantasy', '奇幻'],
    ['history', '历史'],
    ['horror', '恐怖'],
    ['music', '音乐'],
    ['mystery', '悬疑'],
    ['romance', '爱情'],
    ['science_fiction', 'science fiction', 'sci-fi', 'scifi', 'sf', '科幻'],
    ['thriller', '惊悚'],
    ['war', '战争'],
    ['western', '西部'],
    ['sports', 'sport', '运动'],
    ['biography', '传记'],
    ['musical', '歌舞'],
    ['short', '短片'],
    ['film_noir', 'film-noir', 'noir', '黑色电影'],
    ['reality_tv', 'reality', 'reality-tv', '真人秀'],
    ['talk_show', 'talk-show', 'talk show', '脱口秀'],
    ['game_show', 'game-show', 'game show', '游戏节目'],
    ['news', '新闻'],
    ['adult', '成人'],
    ['children', 'kids', "children's", '儿童'],
    ['action_adventure', 'action & adventure', '动作冒险'],
    ['scifi_fantasy', 'sci-fi & fantasy', '科幻奇幻'],
    ['war_politics', 'war & politics', '战争政治'],
    ['soap', '肥皂剧'],
    ['suspense', '悬念'],

    // 电视剧特有
    ['miniseries', 'mini-series', '迷你剧'],
    ['tv_movie', 'tv movie', 'tv-movie', '电视电影'],

    // 动画细分
    ['anime', '动漫'],

    // 其他
    ['indie', 'independent', '独立电影'],
    ['cult', '邪典'],
    ['experimental', '实验'],
    ['superhero', '超级英雄'],
    ['martial_arts', 'martial arts', 'wuxia', '武侠'],
    ['kung_fu', 'kung fu', '功夫'],
    ['disaster', '灾难'],
    ['psychological', '心理'],
    ['period', '古装'],
    ['period_drama', 'period drama', '古装剧'],
    ['political', '政治'],
    ['urban', '都市'],
    ['rural', '农村'],
    ['youth', '青春'],
    ['food', '美食'],
    ['travel', '旅游'],
    ['variety', 'variety show', '综艺'],
    ['lifestyle', '生活'],
    ['fashion', '时尚'],
    ['nature', '自然'],
    ['science', '科学'],
    ['technology', '科技'],
    ['business', '商业'],
    ['finance', '金融'],
    ['medical', '医疗'],
    ['legal', '法律'],
    ['espionage', 'spy', '谍战'],
    ['military', '军事'],
    ['mythology', '神话'],
    ['fairy_tale', 'fairy tale', '童话'],
    ['satire', '讽刺'],
    ['parody', '恶搞'],
    ['slice_of_life', 'slice of life', '日常'],
    ['coming_of_age', 'coming of age', '成长'],
    ['romantic_comedy', 'romantic comedy', 'rom-com', '浪漫喜剧'],
    ['dark_comedy', 'dark comedy', 'black comedy', '黑色喜剧'],
    ['slapstick', '闹剧'],
    ['mockumentary', 'found footage', '伪纪录片'],
    ['anthology', '单元剧'],
    ['procedural', '程序剧'],
    ['sitcom', '情景喜剧'],
    ['workplace', 'office', '职场'],
    ['school', 'high school', 'college', 'campus', '校园'],
  ];

  /// 所有变体 -> 规范键的映射（运行时生成）
  static final Map<String, String> _genreToCanonical = _buildGenreToCanonical();

  /// 规范键 -> 中文的映射（运行时生成）
  static final Map<String, String> _canonicalToZh = _buildCanonicalToZh();

  /// 构建 变体 -> 规范键 映射
  static Map<String, String> _buildGenreToCanonical() {
    final map = <String, String>{};
    for (final group in _genreSynonymGroups) {
      if (group.isEmpty) continue;
      final canonical = group.first;
      for (final variant in group) {
        // 英文统一小写作为 key
        final key = variant.toLowerCase().trim();
        map[key] = canonical;
        // 中文直接作为 key（不转小写）
        if (_isChinese(variant)) {
          map[variant.trim()] = canonical;
        }
      }
    }
    return map;
  }

  /// 构建 规范键 -> 中文 映射
  static Map<String, String> _buildCanonicalToZh() {
    final map = <String, String>{};
    for (final group in _genreSynonymGroups) {
      if (group.isEmpty) continue;
      final canonical = group.first;
      // 找到组内的中文名称
      for (final variant in group) {
        if (_isChinese(variant)) {
          map[canonical] = variant;
          break;
        }
      }
    }
    return map;
  }

  /// 判断字符串是否包含中文字符
  static bool _isChinese(String text) => RegExp(r'[\u4e00-\u9fa5]').hasMatch(text);

  /// 兼容旧代码：英文 -> 中文映射
  static Map<String, String> get _genreEnToZh {
    final map = <String, String>{};
    for (final group in _genreSynonymGroups) {
      if (group.isEmpty) continue;
      String? zhName;
      for (final variant in group) {
        if (_isChinese(variant)) {
          zhName = variant;
          break;
        }
      }
      if (zhName != null) {
        for (final variant in group) {
          if (!_isChinese(variant)) {
            map[variant.toLowerCase()] = zhName;
          }
        }
      }
    }
    return map;
  }

  /// 兼容旧代码：中文 -> 英文（规范键）映射
  // ignore: unused_element
  static Map<String, String> get _genreZhToEn {
    final map = <String, String>{};
    for (final group in _genreSynonymGroups) {
      if (group.isEmpty) continue;
      final canonical = group.first;
      for (final variant in group) {
        if (_isChinese(variant)) {
          map[variant] = canonical;
        }
      }
    }
    return map;
  }

  // ==================== 国家/地区映射 ====================

  /// 国家/地区映射表：英文 -> 中文
  static const Map<String, String> _countryEnToZh = {
    // 主要国家
    'united states': '美国',
    'united states of america': '美国',
    'usa': '美国',
    'us': '美国',
    'america': '美国',
    'united kingdom': '英国',
    'uk': '英国',
    'great britain': '英国',
    'britain': '英国',
    'england': '英国',
    'china': '中国',
    'cn': '中国',
    "people's republic of china": '中国',
    'prc': '中国',
    'mainland china': '中国大陆',
    'hong kong': '中国香港',
    'hk': '中国香港',
    'taiwan': '中国台湾',
    'tw': '中国台湾',
    'japan': '日本',
    'jp': '日本',
    'south korea': '韩国',
    'korea': '韩国',
    'kr': '韩国',
    'republic of korea': '韩国',
    'north korea': '朝鲜',
    'india': '印度',
    'in': '印度',
    'thailand': '泰国',
    'th': '泰国',
    'vietnam': '越南',
    'vn': '越南',
    'singapore': '新加坡',
    'sg': '新加坡',
    'malaysia': '马来西亚',
    'my': '马来西亚',
    'indonesia': '印度尼西亚',
    'id': '印度尼西亚',
    'philippines': '菲律宾',
    'ph': '菲律宾',

    // 欧洲
    'france': '法国',
    'fr': '法国',
    'germany': '德国',
    'de': '德国',
    'italy': '意大利',
    'it': '意大利',
    'spain': '西班牙',
    'es': '西班牙',
    'portugal': '葡萄牙',
    'pt': '葡萄牙',
    'russia': '俄罗斯',
    'ru': '俄罗斯',
    'russian federation': '俄罗斯',
    'soviet union': '苏联',
    'ussr': '苏联',
    'netherlands': '荷兰',
    'nl': '荷兰',
    'holland': '荷兰',
    'belgium': '比利时',
    'be': '比利时',
    'switzerland': '瑞士',
    'ch': '瑞士',
    'austria': '奥地利',
    'at': '奥地利',
    'sweden': '瑞典',
    'se': '瑞典',
    'norway': '挪威',
    'no': '挪威',
    'denmark': '丹麦',
    'dk': '丹麦',
    'finland': '芬兰',
    'fi': '芬兰',
    'poland': '波兰',
    'pl': '波兰',
    'czech republic': '捷克',
    'czechia': '捷克',
    'cz': '捷克',
    'hungary': '匈牙利',
    'hu': '匈牙利',
    'greece': '希腊',
    'gr': '希腊',
    'turkey': '土耳其',
    'tr': '土耳其',
    'ireland': '爱尔兰',
    'ie': '爱尔兰',
    'scotland': '苏格兰',
    'wales': '威尔士',
    'ukraine': '乌克兰',
    'ua': '乌克兰',
    'romania': '罗马尼亚',
    'ro': '罗马尼亚',
    'bulgaria': '保加利亚',
    'bg': '保加利亚',
    'croatia': '克罗地亚',
    'hr': '克罗地亚',
    'serbia': '塞尔维亚',
    'rs': '塞尔维亚',
    'slovakia': '斯洛伐克',
    'sk': '斯洛伐克',
    'slovenia': '斯洛文尼亚',
    'si': '斯洛文尼亚',
    'iceland': '冰岛',
    'is': '冰岛',
    'luxembourg': '卢森堡',
    'lu': '卢森堡',

    // 美洲
    'canada': '加拿大',
    'ca': '加拿大',
    'mexico': '墨西哥',
    'mx': '墨西哥',
    'brazil': '巴西',
    'br': '巴西',
    'argentina': '阿根廷',
    'ar': '阿根廷',
    'colombia': '哥伦比亚',
    'co': '哥伦比亚',
    'chile': '智利',
    'cl': '智利',
    'peru': '秘鲁',
    'pe': '秘鲁',
    'venezuela': '委内瑞拉',
    've': '委内瑞拉',
    'cuba': '古巴',
    'cu': '古巴',

    // 大洋洲
    'australia': '澳大利亚',
    'au': '澳大利亚',
    'new zealand': '新西兰',
    'nz': '新西兰',

    // 中东/非洲
    'israel': '以色列',
    'il': '以色列',
    'iran': '伊朗',
    'ir': '伊朗',
    'egypt': '埃及',
    'eg': '埃及',
    'south africa': '南非',
    'za': '南非',
    'morocco': '摩洛哥',
    'ma': '摩洛哥',
    'saudi arabia': '沙特阿拉伯',
    'sa': '沙特阿拉伯',
    'united arab emirates': '阿联酋',
    'uae': '阿联酋',
    'ae': '阿联酋',
    'pakistan': '巴基斯坦',
    'pk': '巴基斯坦',
    'bangladesh': '孟加拉国',
    'bd': '孟加拉国',
    'nepal': '尼泊尔',
    'np': '尼泊尔',
    'sri lanka': '斯里兰卡',
    'lk': '斯里兰卡',
    'myanmar': '缅甸',
    'mm': '缅甸',
    'cambodia': '柬埔寨',
    'kh': '柬埔寨',
    'laos': '老挝',
    'la': '老挝',
    'mongolia': '蒙古',
    'mn': '蒙古',
    'kazakhstan': '哈萨克斯坦',
    'kz': '哈萨克斯坦',

    // 特殊区域
    'european union': '欧盟',
    'eu': '欧盟',
    'macau': '中国澳门',
    'macao': '中国澳门',
    'mo': '中国澳门',
  };

  /// 国家/地区映射表：中文 -> 英文（反向查找）
  static final Map<String, String> _countryZhToEn = {
    for (final entry in _countryEnToZh.entries) entry.value: entry.key,
  };

  // ==================== 公共方法 ====================

  /// 标准化类型名称（返回规范键）
  ///
  /// 将各种形式的类型名称转换为统一的规范键
  /// 例如：'Action', 'action', '动作' -> 'action'
  /// 例如：'Science Fiction', 'Sci-Fi', 'scifi', 'sf', '科幻' -> 'science_fiction'
  static String normalizeGenre(String genre) {
    final trimmed = genre.trim();
    final lower = trimmed.toLowerCase();

    // 优先查找规范键映射
    if (_genreToCanonical.containsKey(lower)) {
      return _genreToCanonical[lower]!;
    }

    // 中文直接查找（不转小写）
    if (_genreToCanonical.containsKey(trimmed)) {
      return _genreToCanonical[trimmed]!;
    }

    // 未找到映射，返回原始值的小写形式
    return lower;
  }

  /// 标准化国家/地区名称（返回标准化的键）
  static String normalizeCountry(String country) {
    final lower = country.toLowerCase().trim();

    // 如果是英文，直接返回小写形式
    if (_countryEnToZh.containsKey(lower)) {
      return lower;
    }

    // 如果是中文，查找对应的英文作为键
    final trimmed = country.trim();
    if (_countryZhToEn.containsKey(trimmed)) {
      return _countryZhToEn[trimmed]!;
    }

    // 未找到映射，返回原始值的小写形式
    return lower;
  }

  /// 获取类型的显示名称
  ///
  /// [genre] 类型名称（任意语言）
  /// [preferChinese] 是否优先显示中文，默认 true
  static String getGenreDisplayName(String genre, {bool preferChinese = true}) {
    final trimmed = genre.trim();
    final lower = trimmed.toLowerCase();

    // 先获取规范键
    final canonical = _genreToCanonical[lower] ??
        _genreToCanonical[trimmed] ??
        lower;

    if (preferChinese) {
      // 优先返回中文
      if (_canonicalToZh.containsKey(canonical)) {
        return _canonicalToZh[canonical]!;
      }
      // 尝试用旧映射
      if (_genreEnToZh.containsKey(lower)) {
        return _genreEnToZh[lower]!;
      }
      // 已经是中文
      if (_isChinese(trimmed)) {
        return trimmed;
      }
    } else {
      // 返回规范键（首字母大写）
      return _capitalizeFirst(canonical.replaceAll('_', ' '));
    }

    // 未找到映射，返回原始值
    return trimmed.isNotEmpty ? trimmed : lower;
  }

  /// 获取国家/地区的显示名称
  ///
  /// [country] 国家/地区名称（任意语言）
  /// [preferChinese] 是否优先显示中文，默认 true
  static String getCountryDisplayName(String country, {bool preferChinese = true}) {
    final lower = country.toLowerCase().trim();
    final trimmed = country.trim();

    if (preferChinese) {
      // 优先返回中文
      if (_countryEnToZh.containsKey(lower)) {
        return _countryEnToZh[lower]!;
      }
      // 已经是中文
      if (_countryZhToEn.containsKey(trimmed)) {
        return trimmed;
      }
    } else {
      // 优先返回英文
      if (_countryZhToEn.containsKey(trimmed)) {
        return _countryZhToEn[trimmed]!;
      }
      // 已经是英文
      if (_countryEnToZh.containsKey(lower)) {
        return _capitalizeWords(lower);
      }
    }

    // 未找到映射，返回原始值
    return trimmed.isNotEmpty ? trimmed : lower;
  }

  /// 合并类型列表（去除重复的多语言变体）
  ///
  /// [genres] 原始类型列表
  /// [preferChinese] 返回的列表是否使用中文名称
  /// 返回去重后的类型列表
  static List<String> mergeGenres(List<String> genres, {bool preferChinese = true}) {
    final normalized = <String, String>{}; // key -> displayName

    for (final genre in genres) {
      if (genre.isEmpty) continue;
      final key = normalizeGenre(genre);
      if (!normalized.containsKey(key)) {
        normalized[key] = getGenreDisplayName(genre, preferChinese: preferChinese);
      }
    }

    final result = normalized.values.toList()..sort();
    return result;
  }

  /// 合并国家/地区列表（去除重复的多语言变体）
  ///
  /// [countries] 原始国家/地区列表
  /// [preferChinese] 返回的列表是否使用中文名称
  /// 返回去重后的国家/地区列表
  static List<String> mergeCountries(List<String> countries, {bool preferChinese = true}) {
    final normalized = <String, String>{}; // key -> displayName

    for (final country in countries) {
      if (country.isEmpty) continue;
      final key = normalizeCountry(country);
      if (!normalized.containsKey(key)) {
        normalized[key] = getCountryDisplayName(country, preferChinese: preferChinese);
      }
    }

    final result = normalized.values.toList()..sort();
    return result;
  }

  /// 检查两个类型名称是否相同（考虑多语言）
  static bool isSameGenre(String genre1, String genre2) =>
      normalizeGenre(genre1) == normalizeGenre(genre2);

  /// 检查两个国家/地区名称是否相同（考虑多语言）
  static bool isSameCountry(String country1, String country2) =>
      normalizeCountry(country1) == normalizeCountry(country2);

  /// 首字母大写
  static String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// 每个单词首字母大写
  static String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map(_capitalizeFirst).join(' ');
  }
}
