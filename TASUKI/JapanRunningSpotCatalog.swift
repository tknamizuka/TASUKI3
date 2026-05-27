import Foundation

/// 都道府県別の主要ランニングスポット（公園・河川敷・陸上競技場など）。
struct JapanRunningSpot: Identifiable, Hashable {
    let id: String
    let prefecture: String
    let name: String
    let detail: String

    var displayLabel: String {
        if detail.isEmpty { return name }
        return "\(name)（\(detail)）"
    }
}

enum JapanRunningSpotCatalog {
    /// 47都道府県（`海外` を除く）の代表スポット。各県6〜8件程度。
    static let all: [JapanRunningSpot] = [
        // 北海道・東北
        .init(id: "hk-1", prefecture: "北海道", name: "豊平川河川敷", detail: "五輪大橋〜幌平橋・片道最大約14km"),
        .init(id: "hk-2", prefecture: "北海道", name: "大通公園", detail: "札幌中心・東西約1.5km"),
        .init(id: "hk-3", prefecture: "北海道", name: "中島公園", detail: "豊平川ランナー定番の拠点"),
        .init(id: "hk-4", prefecture: "北海道", name: "モエレ沼公園", detail: "札幌東区・広大な園内周回"),
        .init(id: "hk-5", prefecture: "北海道", name: "円山公園", detail: "札幌・木陰の多い周回"),
        .init(id: "hk-6", prefecture: "北海道", name: "真駒内公園", detail: "札幌南区・広い園内と豊平川沿い"),
        .init(id: "hk-7", prefecture: "北海道", name: "前田森林公園", detail: "札幌手稲区・直線路と緑地"),

        .init(id: "ao-1", prefecture: "青森県", name: "青森県立中央公園", detail: "陸上競技場・周回コース"),
        .init(id: "ao-2", prefecture: "青森県", name: "浅虫海岸遊歩道", detail: "海沿いジョギング"),
        .init(id: "ao-3", prefecture: "青森県", name: "合浦公園", detail: "青森市・海浜公園"),
        .init(id: "ao-4", prefecture: "青森県", name: "弘前公園", detail: "城跡外周・朝ラン向け"),
        .init(id: "ao-5", prefecture: "青森県", name: "八戸公園", detail: "広い園内の起伏コース"),
        .init(id: "ao-6", prefecture: "青森県", name: "新青森県総合運動公園", detail: "陸上競技場周辺・練習向け"),
        .init(id: "ao-7", prefecture: "青森県", name: "十和田市中央公園", detail: "中心部の公園周回"),

        .init(id: "iw-1", prefecture: "岩手県", name: "岩手県営運動公園", detail: "盛岡・陸上トラック"),
        .init(id: "iw-2", prefecture: "岩手県", name: "北上川河川敷", detail: "長距離河川コース"),
        .init(id: "iw-3", prefecture: "岩手県", name: "高松公園", detail: "盛岡市・池周辺の周回"),
        .init(id: "iw-4", prefecture: "岩手県", name: "盛岡城跡公園", detail: "中心部・坂道刺激あり"),
        .init(id: "iw-5", prefecture: "岩手県", name: "御所湖広域公園", detail: "湖畔ラン向け"),
        .init(id: "iw-6", prefecture: "岩手県", name: "北上総合運動公園", detail: "陸上競技場周辺・周回"),
        .init(id: "iw-7", prefecture: "岩手県", name: "雫石川河川敷", detail: "盛岡西側・川沿いロング"),

        .init(id: "mg-1", prefecture: "宮城県", name: "広瀬川河川敷", detail: "仙台の定番・長距離可"),
        .init(id: "mg-2", prefecture: "宮城県", name: "広瀬川澱緑地公園", detail: "タータン1km・スピード練習向け"),
        .init(id: "mg-3", prefecture: "宮城県", name: "榴岡公園", detail: "仙台駅東側・周回"),
        .init(id: "mg-4", prefecture: "宮城県", name: "台原森林公園", detail: "木陰と起伏のある園内"),
        .init(id: "mg-5", prefecture: "宮城県", name: "七北田公園", detail: "泉区・フラットな周回"),
        .init(id: "mg-6", prefecture: "宮城県", name: "宮城県総合運動公園", detail: "利府町・競技場周辺"),
        .init(id: "mg-7", prefecture: "宮城県", name: "弘進ゴムアスリートパーク仙台", detail: "陸上競技場周辺"),

        .init(id: "ak-1", prefecture: "秋田県", name: "秋田県立中央公園", detail: "運動公園・周回"),
        .init(id: "ak-2", prefecture: "秋田県", name: "雄物川河川敷", detail: "秋田市・河川敷"),
        .init(id: "ak-3", prefecture: "秋田県", name: "千秋公園", detail: "秋田市中心・城跡公園"),
        .init(id: "ak-4", prefecture: "秋田県", name: "八橋運動公園", detail: "競技場周辺・練習向け"),
        .init(id: "ak-5", prefecture: "秋田県", name: "大森山公園", detail: "坂道を含む園内ラン"),
        .init(id: "ak-6", prefecture: "秋田県", name: "小泉潟公園", detail: "秋田市北部・広い園内"),
        .init(id: "ak-7", prefecture: "秋田県", name: "本荘公園", detail: "由利本荘・城跡周回"),

        .init(id: "yg-1", prefecture: "山形県", name: "霞城公園", detail: "山形市・城跡公園"),
        .init(id: "yg-2", prefecture: "山形県", name: "最上川河川敷", detail: "庄内・長距離区間"),
        .init(id: "yg-3", prefecture: "山形県", name: "山形県総合運動公園", detail: "天童市・陸上競技場"),
        .init(id: "yg-4", prefecture: "山形県", name: "馬見ヶ崎川河川敷", detail: "山形市・河川沿い"),
        .init(id: "yg-5", prefecture: "山形県", name: "鶴岡公園", detail: "城跡外周・朝ラン向け"),
        .init(id: "yg-6", prefecture: "山形県", name: "西公園", detail: "山形市・芝生広場と周回"),
        .init(id: "yg-7", prefecture: "山形県", name: "酒田北港緑地", detail: "酒田市・海沿いラン"),

        .init(id: "fs-1", prefecture: "福島県", name: "南湖公園", detail: "白河市・周回"),
        .init(id: "fs-2", prefecture: "福島県", name: "阿武隈川河川敷", detail: "郡山・福島方面"),
        .init(id: "fs-3", prefecture: "福島県", name: "あづま総合運動公園", detail: "福島市・広い園内周回"),
        .init(id: "fs-4", prefecture: "福島県", name: "開成山公園", detail: "郡山市・市民ランの定番"),
        .init(id: "fs-5", prefecture: "福島県", name: "鶴ヶ城公園", detail: "会津若松・城跡周回"),
        .init(id: "fs-6", prefecture: "福島県", name: "21世紀記念公園 麓山の杜", detail: "郡山市・街中の緑地"),
        .init(id: "fs-7", prefecture: "福島県", name: "逢瀬公園", detail: "郡山市西部・起伏あり"),

        // 関東
        .init(id: "ib-1", prefecture: "茨城県", name: "千波公園", detail: "水戸市・河川沿い"),
        .init(id: "ib-2", prefecture: "茨城県", name: "常磐緑地公園", detail: "ひたちなか・海浜"),
        .init(id: "ib-3", prefecture: "茨城県", name: "洞峰公園", detail: "つくば市・周回"),
        .init(id: "ib-4", prefecture: "茨城県", name: "霞ヶ浦湖岸", detail: "土浦・湖沿い長距離"),
        .init(id: "ib-5", prefecture: "茨城県", name: "国営ひたち海浜公園", detail: "広大な園内ラン"),
        .init(id: "ib-6", prefecture: "茨城県", name: "科学万博記念公園", detail: "つくば市・緑地周回"),
        .init(id: "ib-7", prefecture: "茨城県", name: "ひたちなか市総合運動公園", detail: "競技場周辺・練習向け"),

        .init(id: "tc-1", prefecture: "栃木県", name: "鹿沼運動公園", detail: "陸上競技場・周回"),
        .init(id: "tc-2", prefecture: "栃木県", name: "渡良瀬川河川敷", detail: "足利・桐生方面"),
        .init(id: "tc-3", prefecture: "栃木県", name: "栃木県総合運動公園", detail: "宇都宮・陸上競技場周辺"),
        .init(id: "tc-4", prefecture: "栃木県", name: "井頭公園", detail: "真岡市・森の周回"),
        .init(id: "tc-5", prefecture: "栃木県", name: "八幡山公園", detail: "宇都宮市・起伏あり"),
        .init(id: "tc-6", prefecture: "栃木県", name: "鬼怒グリーンパーク", detail: "高根沢・水辺の周回"),
        .init(id: "tc-7", prefecture: "栃木県", name: "小山総合公園", detail: "思川沿い・広い園内"),

        .init(id: "gm-1", prefecture: "群馬県", name: "群馬県総合運動公園", detail: "前橋・陸上トラック"),
        .init(id: "gm-2", prefecture: "群馬県", name: "利根川河川敷", detail: "太田・館林方面・長距離"),
        .init(id: "gm-3", prefecture: "群馬県", name: "敷島公園", detail: "前橋市・競技場周辺"),
        .init(id: "gm-4", prefecture: "群馬県", name: "高崎公園", detail: "中心部・短め周回"),
        .init(id: "gm-5", prefecture: "群馬県", name: "烏川河川敷", detail: "高崎市・河川沿い"),
        .init(id: "gm-6", prefecture: "群馬県", name: "浜川運動公園", detail: "高崎市・競技場周辺"),
        .init(id: "gm-7", prefecture: "群馬県", name: "観音山ファミリーパーク", detail: "丘陵地・起伏あり"),

        .init(id: "st-1", prefecture: "埼玉県", name: "さいたま市大宮公園", detail: "周回・市民ランナー多数"),
        .init(id: "st-2", prefecture: "埼玉県", name: "荒川河川敷", detail: "さいたま・川口区間"),
        .init(id: "st-3", prefecture: "埼玉県", name: "彩湖・道満グリーンパーク", detail: "湖畔周回・ロング走向け"),
        .init(id: "st-4", prefecture: "埼玉県", name: "別所沼公園", detail: "さいたま市・短め周回"),
        .init(id: "st-5", prefecture: "埼玉県", name: "所沢航空記念公園", detail: "広い園内・周回"),
        .init(id: "st-6", prefecture: "埼玉県", name: "しらこばと運動公園", detail: "越谷市・運動施設周辺"),
        .init(id: "st-7", prefecture: "埼玉県", name: "越谷レイクタウン湖畔", detail: "水辺のフラットコース"),

        .init(id: "cb-1", prefecture: "千葉県", name: "幕張海浜公園", detail: "海沿い・フラット"),
        .init(id: "cb-2", prefecture: "千葉県", name: "印旛沼周辺", detail: "周回・サイクリングロード併用"),
        .init(id: "cb-3", prefecture: "千葉県", name: "稲毛海浜公園", detail: "海沿い・フラット"),
        .init(id: "cb-4", prefecture: "千葉県", name: "手賀沼遊歩道", detail: "柏・我孫子の湖畔コース"),
        .init(id: "cb-5", prefecture: "千葉県", name: "青葉の森公園", detail: "千葉市・緑の多い周回"),
        .init(id: "cb-6", prefecture: "千葉県", name: "千葉県総合スポーツセンター", detail: "陸上競技場周辺・練習向け"),
        .init(id: "cb-7", prefecture: "千葉県", name: "浦安市総合公園", detail: "東京湾沿い・フラット"),

        .init(id: "tk-1", prefecture: "東京都", name: "皇居外周", detail: "約5km・信号なし"),
        .init(id: "tk-2", prefecture: "東京都", name: "駒沢オリンピック公園", detail: "約2.1km/周・ランナー専用レーン"),
        .init(id: "tk-3", prefecture: "東京都", name: "代々木公園", detail: "約1.3〜1.7km/周"),
        .init(id: "tk-4", prefecture: "東京都", name: "国営昭和記念公園", detail: "立川・2.5/3.9/5.6km公式コース"),
        .init(id: "tk-5", prefecture: "東京都", name: "多摩川河川敷", detail: "長距離練習の定番"),
        .init(id: "tk-6", prefecture: "東京都", name: "神宮外苑", detail: "約1.3km/周・都心の定番"),
        .init(id: "tk-7", prefecture: "東京都", name: "砧公園", detail: "世田谷・緑の多い周回"),
        .init(id: "tk-8", prefecture: "東京都", name: "木場公園", detail: "江東区・フラットな園内"),
        .init(id: "tk-9", prefecture: "東京都", name: "井の頭恩賜公園", detail: "池周辺・吉祥寺の定番"),
        .init(id: "tk-10", prefecture: "東京都", name: "水元公園", detail: "葛飾区・水辺と広い園内"),
        .init(id: "tk-11", prefecture: "東京都", name: "お台場海浜公園", detail: "湾岸のフラットコース"),

        .init(id: "kn-1", prefecture: "神奈川県", name: "横浜みなとみらい", detail: "臨港パーク・海沿い"),
        .init(id: "kn-2", prefecture: "神奈川県", name: "大岡川河川敷", detail: "横浜市・河川遊歩道"),
        .init(id: "kn-3", prefecture: "神奈川県", name: "三浦海岸", detail: "湘南・海沿いジョギング"),
        .init(id: "kn-4", prefecture: "神奈川県", name: "山下公園", detail: "横浜港沿いの定番"),
        .init(id: "kn-5", prefecture: "神奈川県", name: "境川サイクリングロード", detail: "藤沢・大和方面の長距離"),
        .init(id: "kn-6", prefecture: "神奈川県", name: "等々力緑地", detail: "川崎市・競技場周辺"),
        .init(id: "kn-7", prefecture: "神奈川県", name: "新横浜公園", detail: "日産スタジアム周辺・周回"),
        .init(id: "kn-8", prefecture: "神奈川県", name: "湘南海岸公園", detail: "藤沢・海沿いジョギング"),
        .init(id: "kn-9", prefecture: "神奈川県", name: "海の公園", detail: "横浜金沢区・海辺の周回"),

        // 中部・北陸
        .init(id: "ng-1", prefecture: "新潟県", name: "万代・白山公園", detail: "新潟市中心"),
        .init(id: "ng-2", prefecture: "新潟県", name: "信濃川河川敷", detail: "長岡・燕区間"),
        .init(id: "ng-3", prefecture: "新潟県", name: "やすらぎ堤", detail: "新潟市・信濃川沿い"),
        .init(id: "ng-4", prefecture: "新潟県", name: "鳥屋野潟公園", detail: "新潟市・湖畔周回"),
        .init(id: "ng-5", prefecture: "新潟県", name: "上越市高田城址公園", detail: "城跡外周・朝ラン向け"),
        .init(id: "ng-6", prefecture: "新潟県", name: "新潟県スポーツ公園", detail: "ビッグスワン周辺・広い園内"),
        .init(id: "ng-7", prefecture: "新潟県", name: "国営越後丘陵公園", detail: "長岡市・起伏ある園内"),

        .init(id: "ty-1", prefecture: "富山県", name: "富岩運動公園", detail: "陸上競技場・周回"),
        .init(id: "ty-2", prefecture: "富山県", name: "常願寺川河川敷", detail: "富山市"),
        .init(id: "ty-3", prefecture: "富山県", name: "富岩運河環水公園", detail: "水辺のフラット周回"),
        .init(id: "ty-4", prefecture: "富山県", name: "城址公園", detail: "富山市中心・短め周回"),
        .init(id: "ty-5", prefecture: "富山県", name: "県民公園太閤山ランド", detail: "射水市・広い園内"),
        .init(id: "ty-6", prefecture: "富山県", name: "富山県総合運動公園", detail: "競技場周辺・練習向け"),
        .init(id: "ty-7", prefecture: "富山県", name: "松川公園", detail: "富山市中心・水辺の周回"),

        .init(id: "is-1", prefecture: "石川県", name: "金沢城公園", detail: "兼六園隣接・城跡"),
        .init(id: "is-2", prefecture: "石川県", name: "犀川河川敷", detail: "金沢市・河川敷"),
        .init(id: "is-3", prefecture: "石川県", name: "大乗寺丘陵公園", detail: "金沢市・起伏と眺望"),
        .init(id: "is-4", prefecture: "石川県", name: "内灘海岸", detail: "海沿いジョギング"),
        .init(id: "is-5", prefecture: "石川県", name: "手取川河川敷", detail: "白山・川沿いロング"),
        .init(id: "is-6", prefecture: "石川県", name: "西部緑地公園", detail: "金沢市・競技場周辺"),
        .init(id: "is-7", prefecture: "石川県", name: "卯辰山公園", detail: "金沢市・坂道と眺望"),

        .init(id: "fi-1", prefecture: "福井県", name: "福井県運動公園", detail: "陸上トラック・周回"),
        .init(id: "fi-2", prefecture: "福井県", name: "足羽川河川敷", detail: "福井市"),
        .init(id: "fi-3", prefecture: "福井県", name: "足羽山公園", detail: "福井市・坂道練習"),
        .init(id: "fi-4", prefecture: "福井県", name: "敦賀港周辺", detail: "港沿いジョギング"),
        .init(id: "fi-5", prefecture: "福井県", name: "三国サンセットビーチ", detail: "海沿いラン向け"),
        .init(id: "fi-6", prefecture: "福井県", name: "福井市中央公園", detail: "中心部・短め周回"),
        .init(id: "fi-7", prefecture: "福井県", name: "九頭竜川河川敷", detail: "福井市北部・川沿い"),

        .init(id: "yn-1", prefecture: "山梨県", name: "富士川河川敷", detail: "長距離・富士山ビュー"),
        .init(id: "yn-2", prefecture: "山梨県", name: "山梨県立芸術公園", detail: "小瀬周辺"),
        .init(id: "yn-3", prefecture: "山梨県", name: "小瀬スポーツ公園", detail: "甲府・陸上競技場周辺"),
        .init(id: "yn-4", prefecture: "山梨県", name: "河口湖畔", detail: "富士山ビューの湖畔ラン"),
        .init(id: "yn-5", prefecture: "山梨県", name: "山中湖交流プラザきらら周辺", detail: "湖畔ロング向け"),
        .init(id: "yn-6", prefecture: "山梨県", name: "緑が丘スポーツ公園", detail: "甲府市・競技場周辺"),
        .init(id: "yn-7", prefecture: "山梨県", name: "曽根丘陵公園", detail: "甲府盆地南側・起伏あり"),

        .init(id: "nn-1", prefecture: "長野県", name: "善光寺公園", detail: "長野市"),
        .init(id: "nn-2", prefecture: "長野県", name: "長野運動公園", detail: "陸上競技場"),
        .init(id: "nn-3", prefecture: "長野県", name: "松本城公園", detail: "城跡外周・街ラン"),
        .init(id: "nn-4", prefecture: "長野県", name: "諏訪湖畔", detail: "湖一周約16km"),
        .init(id: "nn-5", prefecture: "長野県", name: "南長野運動公園", detail: "競技場周辺・周回"),
        .init(id: "nn-6", prefecture: "長野県", name: "軽井沢風越公園", detail: "高原ラン・運動施設周辺"),
        .init(id: "nn-7", prefecture: "長野県", name: "上田城跡公園", detail: "城跡外周・街ラン"),

        .init(id: "gf-1", prefecture: "岐阜県", name: "岐阜県総合運動場", detail: "各務原・陸上"),
        .init(id: "gf-2", prefecture: "岐阜県", name: "長良川河川敷", detail: "岐阜市・川沿い"),
        .init(id: "gf-3", prefecture: "岐阜県", name: "岐阜メモリアルセンター", detail: "競技場周辺・練習向け"),
        .init(id: "gf-4", prefecture: "岐阜県", name: "各務原市民公園", detail: "市街地の周回"),
        .init(id: "gf-5", prefecture: "岐阜県", name: "木曽三川公園", detail: "河川敷・広い園内"),
        .init(id: "gf-6", prefecture: "岐阜県", name: "岐阜公園", detail: "金華山ふもと・起伏あり"),
        .init(id: "gf-7", prefecture: "岐阜県", name: "大垣公園", detail: "城跡周辺・短め周回"),

        .init(id: "sz-1", prefecture: "静岡県", name: "安倍川河川敷", detail: "静岡市・長距離"),
        .init(id: "sz-2", prefecture: "静岡県", name: "浜名湖周辺", detail: "舘山寺・舞阪方面"),
        .init(id: "sz-3", prefecture: "静岡県", name: "駿府城公園", detail: "静岡市・周回"),
        .init(id: "sz-4", prefecture: "静岡県", name: "佐鳴湖公園", detail: "浜松市・湖畔周回"),
        .init(id: "sz-5", prefecture: "静岡県", name: "草薙総合運動場", detail: "静岡市・競技場周辺"),
        .init(id: "sz-6", prefecture: "静岡県", name: "遠州灘海浜公園", detail: "浜松市・海沿い緑地"),
        .init(id: "sz-7", prefecture: "静岡県", name: "富士中央公園", detail: "富士市・芝生広場周辺"),

        .init(id: "ai-1", prefecture: "愛知県", name: "名城公園", detail: "名古屋・約1.2km/周"),
        .init(id: "ai-2", prefecture: "愛知県", name: "名古屋城公園", detail: "観光と兼ねた朝ラン"),
        .init(id: "ai-3", prefecture: "愛知県", name: "庄内川河川敷", detail: "一宮・長距離"),
        .init(id: "ai-4", prefecture: "愛知県", name: "鶴舞公園", detail: "名古屋市・街中の周回"),
        .init(id: "ai-5", prefecture: "愛知県", name: "大高緑地", detail: "名古屋市緑区・起伏あり"),
        .init(id: "ai-6", prefecture: "愛知県", name: "庄内緑地", detail: "名古屋市西区・フラット周回"),
        .init(id: "ai-7", prefecture: "愛知県", name: "愛・地球博記念公園", detail: "長久手市・広い園内"),

        .init(id: "me-1", prefecture: "三重県", name: "員弁郡運動公園", detail: "陸上競技場"),
        .init(id: "me-2", prefecture: "三重県", name: "鈴鹿川河川敷", detail: "鈴鹿市"),
        .init(id: "me-3", prefecture: "三重県", name: "三重交通Gスポーツの杜鈴鹿", detail: "陸上競技場周辺"),
        .init(id: "me-4", prefecture: "三重県", name: "津偕楽公園", detail: "津市・短め周回"),
        .init(id: "me-5", prefecture: "三重県", name: "伊勢宮川河川敷", detail: "伊勢市・川沿い"),
        .init(id: "me-6", prefecture: "三重県", name: "中勢グリーンパーク", detail: "津市・広い芝生と園路"),
        .init(id: "me-7", prefecture: "三重県", name: "霞ヶ浦緑地", detail: "四日市市・海沿い緑地"),

        // 近畿
        .init(id: "sg-1", prefecture: "滋賀県", name: "琵琶湖疏水・大津", detail: "景観の良い水路"),
        .init(id: "sg-2", prefecture: "滋賀県", name: "滋賀県立運動公園", detail: "守山市"),
        .init(id: "sg-3", prefecture: "滋賀県", name: "皇子山総合運動公園", detail: "大津市・競技場周辺"),
        .init(id: "sg-4", prefecture: "滋賀県", name: "なぎさ公園", detail: "大津市・琵琶湖沿い"),
        .init(id: "sg-5", prefecture: "滋賀県", name: "矢橋帰帆島公園", detail: "草津市・湖岸周回"),
        .init(id: "sg-6", prefecture: "滋賀県", name: "希望が丘文化公園", detail: "野洲・竜王・湖南の広域公園"),
        .init(id: "sg-7", prefecture: "滋賀県", name: "豊公園", detail: "長浜城周辺・湖岸ラン"),

        .init(id: "ky-1", prefecture: "京都府", name: "京都御苑（御所）外周", detail: "約4km/周"),
        .init(id: "ky-2", prefecture: "京都府", name: "鴨川ジョギングコース", detail: "京都市公式・最大約9km"),
        .init(id: "ky-3", prefecture: "京都府", name: "円山公園〜平安神宮", detail: "早朝ラン向け"),
        .init(id: "ky-4", prefecture: "京都府", name: "宝が池公園", detail: "池周回・木陰あり"),
        .init(id: "ky-5", prefecture: "京都府", name: "桂川サイクリングロード", detail: "ロング走向け"),
        .init(id: "ky-6", prefecture: "京都府", name: "西京極総合運動公園", detail: "競技場周辺・練習向け"),
        .init(id: "ky-7", prefecture: "京都府", name: "嵐山渡月橋周辺", detail: "桂川沿い・景観ラン"),

        .init(id: "os-1", prefecture: "大阪府", name: "大阪城公園", detail: "ロング約3.5km/ショート約2.9km"),
        .init(id: "os-2", prefecture: "大阪府", name: "万博記念公園", detail: "吹田市・広大な園内"),
        .init(id: "os-3", prefecture: "大阪府", name: "住吉公園", detail: "住吉・河川沿い"),
        .init(id: "os-4", prefecture: "大阪府", name: "長居公園", detail: "約2.8km/周・ランナー定番"),
        .init(id: "os-5", prefecture: "大阪府", name: "中之島公園", detail: "水都大阪の街ラン"),
        .init(id: "os-6", prefecture: "大阪府", name: "淀川河川公園", detail: "河川敷ロング走の定番"),
        .init(id: "os-7", prefecture: "大阪府", name: "大泉緑地", detail: "堺市・木陰の多い周回"),
        .init(id: "os-8", prefecture: "大阪府", name: "服部緑地", detail: "豊中市・広い園内"),

        .init(id: "hg-1", prefecture: "兵庫県", name: "王子公園", detail: "神戸市・周回"),
        .init(id: "hg-2", prefecture: "兵庫県", name: "神戸メリケンパーク", detail: "ハーバーランド・海沿い"),
        .init(id: "hg-3", prefecture: "兵庫県", name: "東遊園地", detail: "須磨・海岸"),
        .init(id: "hg-4", prefecture: "兵庫県", name: "武庫川河川敷", detail: "西宮・尼崎方面の定番"),
        .init(id: "hg-5", prefecture: "兵庫県", name: "明石公園", detail: "城跡・周回"),
        .init(id: "hg-6", prefecture: "兵庫県", name: "須磨海浜公園", detail: "海沿い・フラット"),
        .init(id: "hg-7", prefecture: "兵庫県", name: "加古川河川敷", detail: "長距離走向けの川沿い"),

        .init(id: "nr-1", prefecture: "奈良県", name: "奈良公園周辺", detail: "早朝・平坦区間"),
        .init(id: "nr-2", prefecture: "奈良県", name: "佐保川河川敷", detail: "奈良市"),
        .init(id: "nr-3", prefecture: "奈良県", name: "橿原運動公園", detail: "陸上競技場周辺"),
        .init(id: "nr-4", prefecture: "奈良県", name: "馬見丘陵公園", detail: "広い園内・起伏あり"),
        .init(id: "nr-5", prefecture: "奈良県", name: "大和川河川敷", detail: "王寺・河川沿い"),
        .init(id: "nr-6", prefecture: "奈良県", name: "平城宮跡歴史公園", detail: "広い芝生とフラットな園路"),
        .init(id: "nr-7", prefecture: "奈良県", name: "明日香村周遊コース", detail: "史跡めぐりの里山ラン"),

        .init(id: "wk-1", prefecture: "和歌山県", name: "紀の川河川公園", detail: "和歌山市"),
        .init(id: "wk-2", prefecture: "和歌山県", name: "白浜海岸", detail: "海沿いジョギング"),
        .init(id: "wk-3", prefecture: "和歌山県", name: "和歌山城公園", detail: "城跡周回・坂道あり"),
        .init(id: "wk-4", prefecture: "和歌山県", name: "片男波公園", detail: "海浜公園・フラット"),
        .init(id: "wk-5", prefecture: "和歌山県", name: "紀三井寺公園", detail: "競技場周辺・練習向け"),
        .init(id: "wk-6", prefecture: "和歌山県", name: "和歌浦周辺", detail: "海辺と景観を楽しむコース"),
        .init(id: "wk-7", prefecture: "和歌山県", name: "河西公園", detail: "和歌山市・広い園内周回"),

        // 中国・四国
        .init(id: "tt-1", prefecture: "鳥取県", name: "水木公園", detail: "鳥取市"),
        .init(id: "tt-2", prefecture: "鳥取県", name: "鳥取砂丘周辺", detail: "景観ラン・トレイル寄り"),
        .init(id: "tt-3", prefecture: "鳥取県", name: "布勢総合運動公園", detail: "鳥取市・競技場周辺"),
        .init(id: "tt-4", prefecture: "鳥取県", name: "湖山池周辺", detail: "湖畔ロング向け"),
        .init(id: "tt-5", prefecture: "鳥取県", name: "米子水鳥公園周辺", detail: "中海沿い・フラット"),
        .init(id: "tt-6", prefecture: "鳥取県", name: "湊山公園", detail: "米子市・中海沿い"),
        .init(id: "tt-7", prefecture: "鳥取県", name: "東郷湖羽合臨海公園", detail: "湖畔のフラットコース"),

        .init(id: "sn-1", prefecture: "島根県", name: "松江城山公園", detail: "堀周り・城跡"),
        .init(id: "sn-2", prefecture: "島根県", name: "宍道湖周辺", detail: "松江市・湖岸"),
        .init(id: "sn-3", prefecture: "島根県", name: "松江総合運動公園", detail: "競技場周辺・練習向け"),
        .init(id: "sn-4", prefecture: "島根県", name: "浜山公園", detail: "出雲市・広い運動公園"),
        .init(id: "sn-5", prefecture: "島根県", name: "斐伊川河川敷", detail: "出雲・川沿い"),
        .init(id: "sn-6", prefecture: "島根県", name: "益田運動公園", detail: "陸上競技場周辺・周回"),
        .init(id: "sn-7", prefecture: "島根県", name: "石見海浜公園", detail: "浜田市・海沿い"),

        .init(id: "oy-1", prefecture: "岡山県", name: "岡山後楽園外周", detail: "城跡・周回"),
        .init(id: "oy-2", prefecture: "岡山県", name: "旭川河川敷", detail: "岡山市・長距離"),
        .init(id: "oy-3", prefecture: "岡山県", name: "岡山県総合グラウンド", detail: "シティライトスタジアム周辺"),
        .init(id: "oy-4", prefecture: "岡山県", name: "倉敷みらい公園", detail: "倉敷市・街中周回"),
        .init(id: "oy-5", prefecture: "岡山県", name: "吉井川河川敷", detail: "東岡山方面・河川沿い"),
        .init(id: "oy-6", prefecture: "岡山県", name: "水島緑地福田公園", detail: "倉敷市・運動施設周辺"),
        .init(id: "oy-7", prefecture: "岡山県", name: "倉敷運動公園", detail: "競技場周辺・練習向け"),

        .init(id: "hs-1", prefecture: "広島県", name: "太田川ランニングロード", detail: "大芝・牛田・約5km"),
        .init(id: "hs-2", prefecture: "広島県", name: "広島城周辺", detail: "中区・観光ラン"),
        .init(id: "hs-3", prefecture: "広島県", name: "千田公園", detail: "市民ランナー向け"),
        .init(id: "hs-4", prefecture: "広島県", name: "平和記念公園周辺", detail: "元安川沿い・街ラン"),
        .init(id: "hs-5", prefecture: "広島県", name: "中央公園", detail: "広島市中心・周回"),
        .init(id: "hs-6", prefecture: "広島県", name: "広島広域公園", detail: "エディオンスタジアム周辺"),
        .init(id: "hs-7", prefecture: "広島県", name: "みなと公園", detail: "宇品・港沿いの周回"),

        .init(id: "yc-1", prefecture: "山口県", name: "常盤公園", detail: "下関市"),
        .init(id: "yc-2", prefecture: "山口県", name: "海峡ゆめ広場", detail: "宇部・海浜"),
        .init(id: "yc-3", prefecture: "山口県", name: "維新百年記念公園", detail: "山口市・競技場周辺"),
        .init(id: "yc-4", prefecture: "山口県", name: "きらら博記念公園", detail: "山口市阿知須・海沿い"),
        .init(id: "yc-5", prefecture: "山口県", name: "錦帯橋周辺", detail: "岩国・河川沿い"),
        .init(id: "yc-6", prefecture: "山口県", name: "下関運動公園", detail: "競技場周辺・練習向け"),
        .init(id: "yc-7", prefecture: "山口県", name: "周南緑地", detail: "徳山エリア・広い緑地"),

        .init(id: "ts-1", prefecture: "徳島県", name: "藍住運動公園", detail: "陸上競技場"),
        .init(id: "ts-2", prefecture: "徳島県", name: "吉野川河川敷", detail: "徳島市"),
        .init(id: "ts-3", prefecture: "徳島県", name: "徳島中央公園", detail: "城跡周辺・中心部"),
        .init(id: "ts-4", prefecture: "徳島県", name: "田宮運動公園", detail: "徳島市・運動施設周辺"),
        .init(id: "ts-5", prefecture: "徳島県", name: "小松海岸", detail: "海沿いジョギング"),
        .init(id: "ts-6", prefecture: "徳島県", name: "鳴門・大塚スポーツパーク", detail: "競技場周辺・周回"),
        .init(id: "ts-7", prefecture: "徳島県", name: "あすたむらんど徳島", detail: "板野町・広い園内"),

        .init(id: "kg-1", prefecture: "香川県", name: "中央公園", detail: "高松市・市民の森"),
        .init(id: "kg-2", prefecture: "香川県", name: "瀬戸大橋記念公園", detail: "坂出市・海沿い"),
        .init(id: "kg-3", prefecture: "香川県", name: "栗林公園周辺", detail: "高松市・朝ラン向け"),
        .init(id: "kg-4", prefecture: "香川県", name: "サンポート高松", detail: "港沿い・フラット"),
        .init(id: "kg-5", prefecture: "香川県", name: "丸亀城周辺", detail: "城跡外周・坂道あり"),
        .init(id: "kg-6", prefecture: "香川県", name: "香川県総合運動公園", detail: "高松市・競技場周辺"),
        .init(id: "kg-7", prefecture: "香川県", name: "さぬき空港公園", detail: "高松空港近く・起伏あり"),

        .init(id: "eh-1", prefecture: "愛媛県", name: "松山城周辺", detail: "城山ハイキングコース"),
        .init(id: "eh-2", prefecture: "愛媛県", name: "円山公園", detail: "松山市"),
        .init(id: "eh-3", prefecture: "愛媛県", name: "城山公園", detail: "松山市中心・周回"),
        .init(id: "eh-4", prefecture: "愛媛県", name: "重信川河川敷", detail: "松山近郊・ロング向け"),
        .init(id: "eh-5", prefecture: "愛媛県", name: "道後公園", detail: "湯築城跡・短め周回"),
        .init(id: "eh-6", prefecture: "愛媛県", name: "愛媛県総合運動公園", detail: "松山市・競技場周辺"),
        .init(id: "eh-7", prefecture: "愛媛県", name: "しまなみ海道サイクリングロード", detail: "今治側・海沿いロング"),

        .init(id: "kc-1", prefecture: "高知県", name: "桃田河川公園", detail: "高知市・河川"),
        .init(id: "kc-2", prefecture: "高知県", name: "鏡野湾", detail: "海岸ジョギング"),
        .init(id: "kc-3", prefecture: "高知県", name: "高知城周辺", detail: "中心部・観光ラン"),
        .init(id: "kc-4", prefecture: "高知県", name: "春野総合運動公園", detail: "競技場周辺・練習向け"),
        .init(id: "kc-5", prefecture: "高知県", name: "鏡川河川敷", detail: "高知市・川沿い"),
        .init(id: "kc-6", prefecture: "高知県", name: "高知市総合運動場", detail: "競技場周辺・練習向け"),
        .init(id: "kc-7", prefecture: "高知県", name: "五台山公園", detail: "坂道と眺望のあるコース"),

        // 九州・沖縄
        .init(id: "fo-1", prefecture: "福岡県", name: "大濠公園", detail: "約2km/周・福岡の定番"),
        .init(id: "fo-2", prefecture: "福岡県", name: "シーサイドももち海浜公園", detail: "海沿い・信号なし"),
        .init(id: "fo-3", prefecture: "福岡県", name: "舞鶴公園", detail: "福岡城跡"),
        .init(id: "fo-4", prefecture: "福岡県", name: "西公園", detail: "福岡市・坂道あり"),
        .init(id: "fo-5", prefecture: "福岡県", name: "海の中道海浜公園", detail: "広大な園内・海沿い"),
        .init(id: "fo-6", prefecture: "福岡県", name: "東平尾公園", detail: "博多の森・競技場周辺"),
        .init(id: "fo-7", prefecture: "福岡県", name: "筑後川河川敷", detail: "久留米・ロング走向け"),
        .init(id: "fo-8", prefecture: "福岡県", name: "勝山公園", detail: "北九州市・小倉城周辺"),

        .init(id: "sg2-1", prefecture: "佐賀県", name: "佐賀市運動場", detail: "陸上トラック"),
        .init(id: "sg2-2", prefecture: "佐賀県", name: "干潟よか公園", detail: "東与賀町・海沿い"),
        .init(id: "sg2-3", prefecture: "佐賀県", name: "佐賀県総合運動場", detail: "競技場周辺・練習向け"),
        .init(id: "sg2-4", prefecture: "佐賀県", name: "神野公園", detail: "佐賀市・短め周回"),
        .init(id: "sg2-5", prefecture: "佐賀県", name: "嘉瀬川河川敷", detail: "佐賀市・川沿い"),
        .init(id: "sg2-6", prefecture: "佐賀県", name: "佐賀県立森林公園", detail: "緑の多い広い園内"),
        .init(id: "sg2-7", prefecture: "佐賀県", name: "唐津城周辺", detail: "海と城跡の景観ラン"),

        .init(id: "ns-1", prefecture: "長崎県", name: "長崎水辺の森公園", detail: "水辺・周回"),
        .init(id: "ns-2", prefecture: "長崎県", name: "大村湾海岸", detail: "大村市・海浜"),
        .init(id: "ns-3", prefecture: "長崎県", name: "長崎県立総合運動公園", detail: "諫早市・陸上競技場"),
        .init(id: "ns-4", prefecture: "長崎県", name: "稲佐山公園", detail: "坂道・眺望ラン"),
        .init(id: "ns-5", prefecture: "長崎県", name: "島原総合運動公園", detail: "競技場周辺・周回"),
        .init(id: "ns-6", prefecture: "長崎県", name: "長崎市総合運動公園かきどまり", detail: "競技場周辺・起伏あり"),
        .init(id: "ns-7", prefecture: "長崎県", name: "佐世保公園", detail: "中心部・短め周回"),

        .init(id: "km-1", prefecture: "熊本県", name: "白川淵公園", detail: "熊本市・河川"),
        .init(id: "km-2", prefecture: "熊本県", name: "水前寺成趣園周辺", detail: "早朝ラン"),
        .init(id: "km-3", prefecture: "熊本県", name: "熊本県民総合運動公園", detail: "陸上競技場・広い園内"),
        .init(id: "km-4", prefecture: "熊本県", name: "熊本城公園", detail: "城跡周辺・街ラン"),
        .init(id: "km-5", prefecture: "熊本県", name: "江津湖公園", detail: "湖畔のフラットコース"),
        .init(id: "km-6", prefecture: "熊本県", name: "坪井川緑地", detail: "熊本市北区・周回"),
        .init(id: "km-7", prefecture: "熊本県", name: "菊陽杉並木公園さんさん", detail: "菊陽町・広い園内"),

        .init(id: "oi-1", prefecture: "大分県", name: "城島公園", detail: "大分市・周回"),
        .init(id: "oi-2", prefecture: "大分県", name: "大分スポーツ公園", detail: "陸上競技場"),
        .init(id: "oi-3", prefecture: "大分県", name: "大分川河川敷", detail: "大分市・ロング向け"),
        .init(id: "oi-4", prefecture: "大分県", name: "別府公園", detail: "別府市・緑の多い周回"),
        .init(id: "oi-5", prefecture: "大分県", name: "田ノ浦ビーチ周辺", detail: "海沿いジョギング"),
        .init(id: "oi-6", prefecture: "大分県", name: "平和市民公園", detail: "大分市・街中の周回"),
        .init(id: "oi-7", prefecture: "大分県", name: "七瀬川自然公園", detail: "水辺と芝生の園内"),

        .init(id: "mz-1", prefecture: "宮崎県", name: "生目台運動公園", detail: "陸上トラック"),
        .init(id: "mz-2", prefecture: "宮崎県", name: "青島公園", detail: "鬼の洗濯板・海岸"),
        .init(id: "mz-3", prefecture: "宮崎県", name: "宮崎県総合運動公園", detail: "木花・陸上競技場周辺"),
        .init(id: "mz-4", prefecture: "宮崎県", name: "大淀川河川敷", detail: "宮崎市・川沿い"),
        .init(id: "mz-5", prefecture: "宮崎県", name: "平和台公園", detail: "宮崎市・起伏あり"),
        .init(id: "mz-6", prefecture: "宮崎県", name: "みやざき臨海公園", detail: "海沿い・フラット"),
        .init(id: "mz-7", prefecture: "宮崎県", name: "西都原運動公園", detail: "西都市・広い園内"),

        .init(id: "ks-1", prefecture: "鹿児島県", name: "錦江湾公園", detail: "鹿児島市・海沿い"),
        .init(id: "ks-2", prefecture: "鹿児島県", name: "桜島フェリー港周辺", detail: "景観ラン"),
        .init(id: "ks-3", prefecture: "鹿児島県", name: "鴨池公園", detail: "陸上競技場周辺・練習向け"),
        .init(id: "ks-4", prefecture: "鹿児島県", name: "甲突川河川敷", detail: "鹿児島市・川沿い"),
        .init(id: "ks-5", prefecture: "鹿児島県", name: "吉野公園", detail: "桜島を望む広い園内"),
        .init(id: "ks-6", prefecture: "鹿児島県", name: "鹿児島ふれあいスポーツランド", detail: "競技場周辺・広い園内"),
        .init(id: "ks-7", prefecture: "鹿児島県", name: "かごしま健康の森公園", detail: "起伏のある緑地ラン"),

        .init(id: "ok-1", prefecture: "沖縄県", name: "奥武山公園", detail: "那覇市・陸上競技場"),
        .init(id: "ok-2", prefecture: "沖縄県", name: "沖縄県総合運動公園", detail: "南城・陸上"),
        .init(id: "ok-3", prefecture: "沖縄県", name: "北谷公園", detail: "美浜・海沿い近く"),
        .init(id: "ok-4", prefecture: "沖縄県", name: "新都心公園", detail: "那覇市・周回"),
        .init(id: "ok-5", prefecture: "沖縄県", name: "宜野湾海浜公園", detail: "海沿い・フラット"),
        .init(id: "ok-6", prefecture: "沖縄県", name: "漫湖公園", detail: "那覇・豊見城の水辺"),
        .init(id: "ok-7", prefecture: "沖縄県", name: "豊崎海浜公園", detail: "豊見城市・海沿い"),
        .init(id: "ok-8", prefecture: "沖縄県", name: "浦添大公園", detail: "起伏と緑の多い園内"),
        .init(id: "ok-9", prefecture: "沖縄県", name: "海洋博公園", detail: "本部町・海沿いの広い園内"),
    ]

    private static let byPrefecture: [String: [JapanRunningSpot]] = Dictionary(
        grouping: all,
        by: \.prefecture
    )

    /// 都道府県のおすすめスポット（入力なし時に表示）。
    static func recommended(for prefecture: String) -> [JapanRunningSpot] {
        byPrefecture[prefecture] ?? []
    }

    /// 都道府県内でキーワードに一致するスポット（部分一致・かな寄りは名前のみ）。
    static func matching(prefecture: String, query: String) -> [JapanRunningSpot] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return recommended(for: prefecture) }
        return recommended(for: prefecture).filter { spot in
            spot.name.lowercased().contains(q)
                || spot.detail.lowercased().contains(q)
                || spot.displayLabel.lowercased().contains(q)
        }
    }

    /// 全県のスポット名（フィルタの許可キーワード補強用）。
    static var allSpotNames: [String] {
        all.map(\.name)
    }
}
