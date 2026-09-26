var chineseNames = {
  ar: "阿拉伯语", bg: "保加利亚语", bn: "孟加拉语", cs: "捷克语", da: "丹麦语",
  de: "德语", el: "希腊语", en: "英语", es: "西班牙语", fa: "波斯语",
  fi: "芬兰语", fr: "法语", he: "希伯来语", hi: "印地语", hr: "克罗地亚语",
  hu: "匈牙利语", id: "印尼语", it: "意大利语", ja: "日语", ko: "韩语",
  ms: "马来语", nl: "荷兰语", no: "挪威语", pl: "波兰语", pt: "葡萄牙语",
  ro: "罗马尼亚语", ru: "俄语", sv: "瑞典语", th: "泰语", tr: "土耳其语",
  uk: "乌克兰语", vi: "越南语", zh: "中文"
}

function decorate(entry) {
  var code = String(entry.code || "")
  var base = code.replace(/\.UTF-8/i, "")
  var parts = base.split(/[_@]/)
  var language = parts[0].toLowerCase()
  var nativeName = ""
  try {
    var locale = Qt.locale(base)
    nativeName = String(locale.nativeLanguageName || "")
  } catch (error) {}
  var chineseName = chineseNames[language] || ""
  var englishName = String(entry.name || "")
  return {
    code: code,
    title: chineseName || nativeName || englishName || code,
    subtitle: englishName || nativeName || code,
    nativeName: nativeName,
    installed: !!entry.installed,
    active: !!entry.active,
    haystack: [code, base, chineseName, englishName, nativeName].join(" ").toLocaleLowerCase()
  }
}

function filter(entries, query) {
  var words = String(query || "").trim().toLocaleLowerCase().split(/\s+/).filter(Boolean)
  var matches = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var found = true
    for (var j = 0; j < words.length; j++) {
      if (entry.haystack.indexOf(words[j]) < 0) { found = false; break }
    }
    if (found) matches.push(entry)
  }
  matches.sort(function(a, b) {
    if (a.active !== b.active) return a.active ? -1 : 1
    if (words.length && a.installed !== b.installed) return a.installed ? -1 : 1
    return a.subtitle.localeCompare(b.subtitle) || a.code.localeCompare(b.code)
  })
  return matches
}
