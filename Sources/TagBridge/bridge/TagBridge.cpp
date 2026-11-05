// TagBridge.cpp – implementation of the pure C interface declared in include/TagBridge.h.
//
// Every exported function catches all C++ exceptions. TagLib objects never leave this file.
// The field mapping implemented here is documented in Sources/TagBridge/MAPPING.md.

#include "TagBridge.h"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <new>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include <sys/stat.h>

#include <zlib.h>

// TagLib
#include "taglib.h"
#include "tag.h"
#include "tfile.h"
#include "tfilestream.h"
#include "tpropertymap.h"
#include "tpicturetype.h"
#include "tstring.h"
#include "tstringlist.h"
#include "tbytevector.h"
#include "tvariant.h"

#include "mpegfile.h"
#include "mpegheader.h"
#include "mpegproperties.h"
#include "id3v1tag.h"
#include "id3v1genres.h"
#include "id3v2tag.h"
#include "id3v2header.h"
#include "id3v2frame.h"
#include "attachedpictureframe.h"
#include "commentsframe.h"
#include "popularimeterframe.h"
#include "textidentificationframe.h"
#include "unsynchronizedlyricsframe.h"

#include "mp4file.h"
#include "mp4tag.h"
#include "mp4item.h"
#include "mp4atom.h"
#include "mp4coverart.h"
#include "mp4itemfactory.h"
#include "mp4properties.h"

#include "flacfile.h"
#include "flacpicture.h"
#include "flacproperties.h"
#include "xiphcomment.h"
#include "vorbisfile.h"
#include "vorbisproperties.h"
#include "opusfile.h"
#include "opusproperties.h"
#include "speexfile.h"
#include "speexproperties.h"
#include "oggflacfile.h"

#include "wavfile.h"
#include "wavproperties.h"
#include "infotag.h"
#include "aifffile.h"
#include "aiffproperties.h"

#include "apefile.h"
#include "apeproperties.h"
#include "apetag.h"
#include "apeitem.h"
#include "wavpackfile.h"
#include "wavpackproperties.h"
#include "mpcfile.h"
#include "mpcproperties.h"

#include "asffile.h"
#include "asftag.h"
#include "asfattribute.h"
#include "asfpicture.h"
#include "asfproperties.h"

#include "dsffile.h"
#include "dsfproperties.h"
#include "dsdifffile.h"
#include "dsdiffproperties.h"
#include "dsdiffdiintag.h"

#include "trueaudiofile.h"
#include "trueaudioproperties.h"

#include "matroskafile.h"
#include "matroskaproperties.h"

#include "shortenfile.h"

#include "modfile.h"
#include "s3mfile.h"
#include "itfile.h"
#include "xmfile.h"

using namespace TagLib;

namespace {

// ====================================================================================
// Small helpers
// ====================================================================================

String fromUTF8(const char *s) {
    return String(s ? s : "", String::UTF8);
}

std::string toUTF8(const String &s) {
    return s.to8Bit(true);
}

StringList fromCArray(const char *const *values, size_t count) {
    StringList list;
    for (size_t i = 0; i < count; ++i) {
        if (values[i] == nullptr) continue;
        String v = fromUTF8(values[i]);
        if (!v.isEmpty()) list.append(v);
    }
    return list;
}

StringList cleaned(const StringList &values) {
    StringList out;
    for (const auto &v : values) {
        if (!v.isEmpty()) out.append(v);
    }
    return out;
}

String joinValues(const StringList &values) {
    return cleaned(values).toString("; ");
}

String firstValue(const StringList &values) {
    for (const auto &v : values) {
        if (!v.isEmpty()) return v;
    }
    return String();
}

StringList dedupe(const StringList &values) {
    StringList out;
    for (const auto &v : values) {
        if (!v.isEmpty() && !out.contains(v)) out.append(v);
    }
    return out;
}

bool isTextField(TBField f) {
    return static_cast<int>(f) >= TB_FIELD_TITLE && static_cast<int>(f) <= TB_FIELD_DATE;
}

bool isIntField(TBField f) {
    return static_cast<int>(f) >= TB_FIELD_YEAR && static_cast<int>(f) <= TB_FIELD_BPM;
}

bool isMultiField(TBField f) {
    return f == TB_FIELD_ARTISTS || f == TB_FIELD_ALBUM_ARTISTS || f == TB_FIELD_COMPOSERS ||
           f == TB_FIELD_GENRES;
}

/// Leading integer of a string ("12", " 7", "12/20" -> 12, "120.6" -> 121 when rounding is wanted).
std::optional<long long> leadingInt(const String &raw, bool roundDecimal = false) {
    std::string s = toUTF8(raw.stripWhiteSpace());
    size_t i = 0;
    bool negative = false;
    if (i < s.size() && (s[i] == '+' || s[i] == '-')) {
        negative = s[i] == '-';
        ++i;
    }
    long long value = 0;
    size_t digits = 0;
    while (i < s.size() && s[i] >= '0' && s[i] <= '9') {
        if (value < 100000000000LL) value = value * 10 + (s[i] - '0');
        ++i;
        ++digits;
    }
    if (digits == 0) return std::nullopt;
    if (roundDecimal && i + 1 < s.size() && (s[i] == '.' || s[i] == ',') && s[i + 1] >= '5' &&
        s[i + 1] <= '9') {
        value += 1;
    }
    return negative ? -value : value;
}

struct NumberPair {
    std::optional<long long> number;
    std::optional<long long> total;
};

NumberPair parsePair(const String &s) {
    NumberPair p;
    if (s.isEmpty()) return p;
    int slash = s.find("/");
    if (slash < 0) {
        p.number = leadingInt(s);
    } else {
        p.number = leadingInt(s.substr(0, static_cast<unsigned int>(slash)));
        p.total = leadingInt(s.substr(static_cast<unsigned int>(slash) + 1));
    }
    return p;
}

String formatPair(std::optional<long long> n, std::optional<long long> t) {
    if (!n && !t) return String();
    String s = String::number(static_cast<int>(n.value_or(0)));
    if (t) s += "/" + String::number(static_cast<int>(*t));
    return s;
}

/// Year of a date string: the first run of four digits ("2024-05-17", "2024", "17.05.2024").
std::optional<long long> yearOfDate(const String &date) {
    std::string s = toUTF8(date);
    for (size_t i = 0; i + 4 <= s.size(); ++i) {
        bool ok = true;
        for (size_t k = 0; k < 4; ++k) {
            if (s[i + k] < '0' || s[i + k] > '9') {
                ok = false;
                break;
            }
        }
        if (!ok) continue;
        // must not be part of a longer number
        if (i > 0 && s[i - 1] >= '0' && s[i - 1] <= '9') continue;
        if (i + 4 < s.size() && s[i + 4] >= '0' && s[i + 4] <= '9') continue;
        return std::stoll(s.substr(i, 4));
    }
    // fall back to a plain number ("999")
    return leadingInt(date);
}

String yearString(long long year) {
    char buf[16];
    std::snprintf(buf, sizeof buf, "%04lld", year);
    return String(buf);
}

bool truthy(const String &raw) {
    String s = raw.stripWhiteSpace().upper();
    if (s.isEmpty()) return false;
    if (s == "TRUE" || s == "YES" || s == "Y" || s == "JA") return true;
    auto n = leadingInt(s);
    return n && *n != 0;
}

// ------------------------------------------------------------------ ratings
// ID3v2 POPM: Windows Media Player full stars 1, 64, 128, 196, 255; half stars as written by
// MediaMonkey / MusicBee (13, 54, 118, 186, 242). Index = half stars (0...10).
const int kPopmTable[11] = {0, 13, 1, 54, 64, 118, 128, 186, 196, 242, 255};

int popmFromRating(long long rating) {
    if (rating <= 0) return 0;
    long long half = (rating + 5) / 10;
    if (half < 1) half = 1;
    if (half > 10) half = 10;
    return kPopmTable[half];
}

long long ratingFromPopm(int popm) {
    if (popm <= 0) return 0;
    for (int h = 1; h <= 10; ++h) {
        if (kPopmTable[h] == popm) return h * 10;
    }
    if (popm < 32) return 20;
    if (popm < 96) return 40;
    if (popm < 160) return 60;
    if (popm < 224) return 80;
    return 100;
}

// ASF WM/SharedUserRating: 0, 1, 25, 50, 75, 99 for 0...5 stars.
const unsigned int kAsfRatingTable[6] = {0, 1, 25, 50, 75, 99};

unsigned int asfFromRating(long long rating) {
    if (rating <= 0) return 0;
    long long stars = (rating + 10) / 20;
    if (stars < 1) stars = 1;
    if (stars > 5) stars = 5;
    return kAsfRatingTable[stars];
}

long long ratingFromAsf(long long value) {
    if (value <= 0) return 0;
    if (value < 13) return 20;
    if (value < 38) return 40;
    if (value < 63) return 60;
    if (value < 87) return 80;
    return 100;
}

// ------------------------------------------------------------------ pictures
struct Pic {
    int type = 3;
    String mimeType;
    String description;
    ByteVector data;
    int width = 0;
    int height = 0;
    int colorDepth = 0;
    int numColors = 0;
};

String sniffImageMime(const ByteVector &d) {
    if (d.size() >= 3 && static_cast<unsigned char>(d[0]) == 0xFF &&
        static_cast<unsigned char>(d[1]) == 0xD8 && static_cast<unsigned char>(d[2]) == 0xFF)
        return "image/jpeg";
    if (d.size() >= 8 && d.startsWith(ByteVector("\x89PNG\r\n\x1a\n", 8))) return "image/png";
    if (d.size() >= 6 && (d.startsWith("GIF87a") || d.startsWith("GIF89a"))) return "image/gif";
    if (d.size() >= 2 && d.startsWith("BM")) return "image/bmp";
    if (d.size() >= 12 && d.startsWith("RIFF") && d.mid(8, 4) == "WEBP") return "image/webp";
    if (d.size() >= 4 && (d.startsWith(ByteVector("II*\0", 4)) || d.startsWith(ByteVector("MM\0*", 4))))
        return "image/tiff";
    if (d.size() >= 12 && d.mid(4, 4) == "ftyp") {
        ByteVector brand = d.mid(8, 4);
        if (brand == "heic" || brand == "heix" || brand == "mif1" || brand == "msf1") return "image/heic";
        if (brand == "avif") return "image/avif";
    }
    return String();
}

String asciiLower(const String &s) {
    std::string u = toUTF8(s);
    for (auto &c : u) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    return String(u, String::UTF8);
}

String normalizedMime(const String &mime, const ByteVector &data) {
    String m = asciiLower(mime.stripWhiteSpace());
    if (m == "image/jpg" || m == "jpg" || m == "jpeg") m = "image/jpeg";
    if (m == "png") m = "image/png";
    if (m.isEmpty()) m = sniffImageMime(data);
    return m;
}

int clampPictureType(int t) {
    return (t < 0 || t > 20) ? 0 : t;
}

// ====================================================================================
// Backends: one per tag format. A backend translates the logical fields into the
// representation of its tag format.
// ====================================================================================

class Backend {
public:
    virtual ~Backend() = default;
    virtual bool supports(TBField f) const = 0;
    virtual StringList getStrings(TBField f) = 0;
    virtual void setStrings(TBField f, const StringList &values) = 0;
    virtual std::optional<long long> getInt(TBField f) = 0;
    virtual void setInt(TBField f, std::optional<long long> value) = 0;
    virtual bool supportsPictures() const { return false; }
    virtual std::vector<Pic> getPictures() { return {}; }
    virtual void setPictures(const std::vector<Pic> &) {}
};

// ------------------------------------------------------------------------------------
// ID3v2
// ------------------------------------------------------------------------------------

const char *const kWMPEmail = "Windows Media Player 9 Series";

class ID3v2Backend final : public Backend {
public:
    using Provider = std::function<ID3v2::Tag *(bool create)>;

    ID3v2Backend(Provider provider, int targetVersion)
        : provider_(std::move(provider)), version_(targetVersion) {}

    bool supports(TBField f) const override {
        return isTextField(f) || isIntField(f);
    }

    StringList getStrings(TBField f) override {
        ID3v2::Tag *t = provider_(false);
        if (!t) return {};
        switch (f) {
        case TB_FIELD_GROUPING: return single(grouping(t));
        case TB_FIELD_WORK: return single(work(t));
        case TB_FIELD_COMMENT: {
            if (auto *c = findComment(t)) {
                if (!c->text().isEmpty()) return single(c->text());
            }
            return single(txxxValue(t, "COMMENT"));  // written like this by ffmpeg
        }
        case TB_FIELD_LYRICS: {
            for (auto *frame : t->frameList("USLT")) {
                if (auto *l = dynamic_cast<ID3v2::UnsynchronizedLyricsFrame *>(frame)) {
                    if (!l->text().isEmpty()) return single(l->text());
                }
            }
            return {};
        }
        case TB_FIELD_GENRES: return genres(t);
        case TB_FIELD_DATE: {
            StringList v = textFrame(t, "TDRC");
            if (v.isEmpty()) v = textFrame(t, "TYER");
            return v;
        }
        default: {
            const char *id = frameID(f);
            if (!id) return {};
            return textFrame(t, id);
        }
        }
    }

    void setStrings(TBField f, const StringList &rawValues) override {
        StringList values = cleaned(rawValues);
        switch (f) {
        case TB_FIELD_GROUPING: {
            ID3v2::Tag *t = provider_(true);
            setGroupingAndWork(t, joinValues(values), work(t));
            return;
        }
        case TB_FIELD_WORK: {
            ID3v2::Tag *t = provider_(true);
            setGroupingAndWork(t, grouping(t), joinValues(values));
            return;
        }
        case TB_FIELD_COMMENT: setComment(joinValues(values)); return;
        case TB_FIELD_LYRICS: setLyrics(joinValues(values)); return;
        case TB_FIELD_DATE: return;  // read-only
        default: {
            const char *id = frameID(f);
            if (!id) return;
            setTextFrame(id, values, isMultiField(f));
            return;
        }
        }
    }

    std::optional<long long> getInt(TBField f) override {
        ID3v2::Tag *t = provider_(false);
        if (!t) return std::nullopt;
        switch (f) {
        case TB_FIELD_YEAR: {
            String d = firstValue(getStrings(TB_FIELD_DATE));
            if (d.isEmpty()) return std::nullopt;
            return yearOfDate(d);
        }
        case TB_FIELD_TRACK_NUMBER: return parsePair(firstValue(textFrame(t, "TRCK"))).number;
        case TB_FIELD_TRACK_TOTAL: return parsePair(firstValue(textFrame(t, "TRCK"))).total;
        case TB_FIELD_DISC_NUMBER: return parsePair(firstValue(textFrame(t, "TPOS"))).number;
        case TB_FIELD_DISC_TOTAL: return parsePair(firstValue(textFrame(t, "TPOS"))).total;
        case TB_FIELD_COMPILATION: {
            StringList v = textFrame(t, "TCMP");
            if (v.isEmpty()) return std::nullopt;
            return truthy(firstValue(v)) ? 1 : 0;
        }
        case TB_FIELD_BPM: return leadingInt(firstValue(textFrame(t, "TBPM")), true);
        case TB_FIELD_RATING: {
            ID3v2::PopularimeterFrame *chosen = nullptr;
            for (auto *frame : t->frameList("POPM")) {
                auto *p = dynamic_cast<ID3v2::PopularimeterFrame *>(frame);
                if (!p) continue;
                if (p->email() == kWMPEmail) {
                    chosen = p;
                    break;
                }
                if (!chosen && p->rating() > 0) chosen = p;
            }
            if (!chosen) return std::nullopt;
            if (chosen->rating() <= 0) return std::nullopt;
            return ratingFromPopm(chosen->rating());
        }
        default: return std::nullopt;
        }
    }

    void setInt(TBField f, std::optional<long long> value) override {
        ID3v2::Tag *t = provider_(true);
        switch (f) {
        case TB_FIELD_YEAR: {
            String current = firstValue(getStrings(TB_FIELD_DATE));
            if (!value) {
                setTextFrame("TDRC", {}, false);
                setTextFrame("TYER", {}, false);
                return;
            }
            if (!current.isEmpty() && yearOfDate(current) == value) return;  // keep full date
            setTextFrame("TDRC", StringList(yearString(*value)), false);
            if (!textFrame(t, "TYER").isEmpty()) setTextFrame("TYER", StringList(yearString(*value)), false);
            return;
        }
        case TB_FIELD_TRACK_NUMBER:
        case TB_FIELD_TRACK_TOTAL:
        case TB_FIELD_DISC_NUMBER:
        case TB_FIELD_DISC_TOTAL: {
            const bool track = f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_TRACK_TOTAL;
            const char *id = track ? "TRCK" : "TPOS";
            NumberPair p = parsePair(firstValue(textFrame(t, id)));
            if (f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_DISC_NUMBER) p.number = value;
            else p.total = value;
            String s = formatPair(p.number, p.total);
            setTextFrame(id, s.isEmpty() ? StringList() : StringList(s), false);
            return;
        }
        case TB_FIELD_COMPILATION:
            setTextFrame("TCMP", (value && *value != 0) ? StringList("1") : StringList(), false);
            return;
        case TB_FIELD_BPM:
            setTextFrame("TBPM", value ? StringList(String::number(static_cast<int>(*value))) : StringList(), false);
            return;
        case TB_FIELD_RATING: setRating(t, value); return;
        default: return;
        }
    }

    bool supportsPictures() const override { return true; }

    std::vector<Pic> getPictures() override {
        std::vector<Pic> out;
        ID3v2::Tag *t = provider_(false);
        if (!t) return out;
        for (auto *frame : t->frameList("APIC")) {
            auto *a = dynamic_cast<ID3v2::AttachedPictureFrame *>(frame);
            if (!a) continue;
            Pic p;
            p.type = clampPictureType(static_cast<int>(a->type()));
            p.mimeType = normalizedMime(a->mimeType(), a->picture());
            p.description = a->description();
            p.data = a->picture();
            out.push_back(p);
        }
        return out;
    }

    void setPictures(const std::vector<Pic> &pics) override {
        ID3v2::Tag *t = provider_(true);
        t->removeFrames("APIC");
        for (const auto &p : pics) {
            auto *a = new ID3v2::AttachedPictureFrame();
            a->setTextEncoding(encodingFor(StringList(p.description)));
            a->setType(static_cast<ID3v2::AttachedPictureFrame::Type>(clampPictureType(p.type)));
            a->setMimeType(p.mimeType.isEmpty() ? sniffImageMime(p.data) : p.mimeType);
            a->setDescription(p.description);
            a->setPicture(p.data);
            t->addFrame(a);
        }
    }

    /// Reason why saving would lose frames, or "" if nothing would be lost.
    std::string lossReason() {
        ID3v2::Tag *t = provider_(false);
        if (!t) return "";
        static const char *const notIn23[] = {"ASPI", "EQU2", "RVA2", "SEEK", "SIGN", "TDRL",
                                              "TDTG", "TMOO", "TPRO", "TSST"};
        static const char *const droppedOnRead[] = {"EQUA", "RVAD", "TRDA", "TSIZ", "CRM", "EQU",
                                                    "LNK",  "RVA",  "TSI"};
        for (auto *frame : t->frameList()) {
            const ByteVector id = frame->frameID();
            if (id.size() != 4)
                return "ID3v2 frame '" + std::string(id.data(), id.size()) + "' cannot be written by TagLib";
            for (const char *x : droppedOnRead) {
                if (id == x)
                    return "ID3v2 frame '" + std::string(x) + "' is not supported by TagLib and would be lost";
            }
            if (version_ == 3) {
                for (const char *x : notIn23) {
                    if (id == x)
                        return "ID3v2.4 frame '" + std::string(x) + "' cannot be stored in the ID3v2.3 tag";
                }
            }
        }
        // TDAT/TIME of ID3v2.3 survive only when TagLib could merge them into the date.
        if (!t->frameList("TDAT").isEmpty() || !t->frameList("TIME").isEmpty()) {
            String date = firstValue(textFrame(t, "TDRC"));
            if (!t->frameList("TDAT").isEmpty() && (t->frameList("TDRC").size() != 1 || date.size() < 10))
                return "ID3v2.3 frame 'TDAT' could not be merged into the date and would be lost";
            if (!t->frameList("TIME").isEmpty() && date.find("T") < 0)
                return "ID3v2.3 frame 'TIME' could not be merged into the date and would be lost";
        }
        return "";
    }

private:
    static StringList single(const String &s) {
        return s.isEmpty() ? StringList() : StringList(s);
    }

    static const char *frameID(TBField f) {
        switch (f) {
        case TB_FIELD_TITLE: return "TIT2";
        case TB_FIELD_ARTISTS: return "TPE1";
        case TB_FIELD_ALBUM: return "TALB";
        case TB_FIELD_ALBUM_ARTISTS: return "TPE2";
        case TB_FIELD_COMPOSERS: return "TCOM";
        case TB_FIELD_GENRES: return "TCON";
        case TB_FIELD_TITLE_SORT: return "TSOT";
        case TB_FIELD_ARTIST_SORT: return "TSOP";
        case TB_FIELD_ALBUM_SORT: return "TSOA";
        case TB_FIELD_ALBUM_ARTIST_SORT: return "TSO2";
        case TB_FIELD_COMPOSER_SORT: return "TSOC";
        case TB_FIELD_COPYRIGHT: return "TCOP";
        case TB_FIELD_PUBLISHER: return "TPUB";
        case TB_FIELD_ISRC: return "TSRC";
        case TB_FIELD_ENCODED_BY: return "TENC";
        default: return nullptr;
        }
    }

    static String::Type encodingFor(const StringList &values) {
        for (const auto &v : values) {
            if (!v.isAscii()) return String::UTF8;  // rendered as UTF-16 in ID3v2.3 by TagLib
        }
        return String::Latin1;
    }

    static StringList textFrame(ID3v2::Tag *t, const ByteVector &id) {
        for (auto *frame : t->frameList(id)) {
            if (auto *tf = dynamic_cast<ID3v2::TextIdentificationFrame *>(frame)) {
                StringList v = cleaned(tf->fieldList());
                if (!v.isEmpty()) return v;
            }
        }
        return {};
    }

    void setTextFrame(const ByteVector &id, const StringList &rawValues, bool multi) {
        ID3v2::Tag *t = provider_(true);
        StringList values = cleaned(rawValues);
        if (values.isEmpty()) {
            t->removeFrames(id);
            return;
        }
        if (values.size() > 1 && (!multi || version_ < 4)) values = StringList(joinValues(values));
        const ID3v2::FrameList existing = t->frameList(id);
        ID3v2::TextIdentificationFrame *target = nullptr;
        for (auto *frame : existing) {
            auto *tf = dynamic_cast<ID3v2::TextIdentificationFrame *>(frame);
            if (tf && !target) {
                target = tf;
            } else {
                t->removeFrame(frame, true);  // duplicates of an edited frame
            }
        }
        if (!target) {
            target = new ID3v2::TextIdentificationFrame(id, encodingFor(values));
            t->addFrame(target);
        }
        target->setTextEncoding(encodingFor(values));
        target->setText(values);
    }

    static ID3v2::UserTextIdentificationFrame *findTXXX(ID3v2::Tag *t, const String &description) {
        const String wanted = description.upper();
        for (auto *frame : t->frameList("TXXX")) {
            auto *u = dynamic_cast<ID3v2::UserTextIdentificationFrame *>(frame);
            if (u && u->description().upper() == wanted) return u;
        }
        return nullptr;
    }

    static String txxxValue(ID3v2::Tag *t, const String &description) {
        auto *u = findTXXX(t, description);
        if (!u) return String();
        StringList fields = u->fieldList();
        if (!fields.isEmpty()) fields.erase(fields.begin());  // description
        return joinValues(fields);
    }

    void setTXXX(ID3v2::Tag *t, const String &description, const String &value) {
        // remove all frames with this description, then add one
        const ID3v2::FrameList frames = t->frameList("TXXX");
        const String wanted = description.upper();
        ID3v2::UserTextIdentificationFrame *keep = nullptr;
        for (auto *frame : frames) {
            auto *u = dynamic_cast<ID3v2::UserTextIdentificationFrame *>(frame);
            if (!u || u->description().upper() != wanted) continue;
            if (!keep && !value.isEmpty()) keep = u;
            else t->removeFrame(u, true);
        }
        if (value.isEmpty()) return;
        if (!keep) {
            keep = new ID3v2::UserTextIdentificationFrame(encodingFor(StringList(value)));
            keep->setDescription(description);
            t->addFrame(keep);
        }
        keep->setTextEncoding(encodingFor(StringList(value).append(keep->description())));
        keep->setText(StringList(value));
    }

    // ----- grouping / work (GRP1, TIT1, TXXX:WORK) – see MAPPING.md
    static bool tit1UsedForGrouping(ID3v2::Tag *t) {
        String grp1 = joinValues(textFrame(t, "GRP1"));
        String tit1 = joinValues(textFrame(t, "TIT1"));
        return !tit1.isEmpty() && (grp1.isEmpty() || grp1 == tit1);
    }

    static String grouping(ID3v2::Tag *t) {
        String grp1 = joinValues(textFrame(t, "GRP1"));
        if (!grp1.isEmpty()) return grp1;
        return joinValues(textFrame(t, "TIT1"));
    }

    static String work(ID3v2::Tag *t) {
        String txxx = txxxValue(t, "WORK");
        if (!txxx.isEmpty()) return txxx;
        if (tit1UsedForGrouping(t)) return String();
        return joinValues(textFrame(t, "TIT1"));
    }

    void setGroupingAndWork(ID3v2::Tag *t, const String &g, const String &w) {
        const String oldGrouping = grouping(t);
        const String tit1 = joinValues(textFrame(t, "TIT1"));
        const bool hadTXXXWork = findTXXX(t, "WORK") != nullptr;
        const bool titHoldsGrouping = !tit1.isEmpty() && tit1 == oldGrouping;

        setTextFrame("GRP1", g.isEmpty() ? StringList() : StringList(g), false);
        if (titHoldsGrouping) {
            // legacy grouping in TIT1 (or a copy of GRP1): keep it in sync, work goes to TXXX
            setTextFrame("TIT1", g.isEmpty() ? StringList() : StringList(g), false);
            setTXXX(t, "WORK", w);
            return;
        }
        if (g.isEmpty()) {
            // Without GRP1 a TIT1 would be read as (legacy) grouping: store the work in TXXX.
            setTextFrame("TIT1", {}, false);
            setTXXX(t, "WORK", w);
            return;
        }
        if (w.isEmpty()) {
            setTextFrame("TIT1", {}, false);
            setTXXX(t, "WORK", String());
            return;
        }
        setTextFrame("TIT1", StringList(w), false);  // iTunes 12.5+: TIT1 = work
        if (hadTXXXWork || w == g) setTXXX(t, "WORK", w);
    }

    // ----- comment (COMM without description)
    static ID3v2::CommentsFrame *findComment(ID3v2::Tag *t) {
        for (auto *frame : t->frameList("COMM")) {
            auto *c = dynamic_cast<ID3v2::CommentsFrame *>(frame);
            if (c && c->description().isEmpty()) return c;
        }
        return nullptr;
    }

    void setComment(const String &text) {
        ID3v2::Tag *t = provider_(true);
        if (findTXXX(t, "COMMENT")) setTXXX(t, "COMMENT", text);  // keep the ffmpeg alias in sync
        if (text.isEmpty()) {
            const ID3v2::FrameList frames = t->frameList("COMM");
            for (auto *frame : frames) {
                auto *c = dynamic_cast<ID3v2::CommentsFrame *>(frame);
                if (c && c->description().isEmpty()) t->removeFrame(c, true);
            }
            return;
        }
        ID3v2::CommentsFrame *c = findComment(t);
        if (!c) {
            c = new ID3v2::CommentsFrame(encodingFor(StringList(text)));
            c->setLanguage("eng");
            t->addFrame(c);
        }
        c->setTextEncoding(encodingFor(StringList(text)));
        c->setText(text);
    }

    // ----- lyrics (USLT)
    void setLyrics(const String &text) {
        ID3v2::Tag *t = provider_(true);
        const ID3v2::FrameList frames = t->frameList("USLT");
        if (text.isEmpty()) {
            t->removeFrames("USLT");
            return;
        }
        ID3v2::UnsynchronizedLyricsFrame *target = nullptr;
        for (auto *frame : frames) {
            if (auto *l = dynamic_cast<ID3v2::UnsynchronizedLyricsFrame *>(frame)) {
                target = l;
                break;
            }
        }
        if (!target) {
            target = new ID3v2::UnsynchronizedLyricsFrame(encodingFor(StringList(text)));
            target->setLanguage("und");
            t->addFrame(target);
        }
        target->setTextEncoding(encodingFor(StringList(text).append(target->description())));
        target->setText(text);
    }

    // ----- rating (POPM)
    void setRating(ID3v2::Tag *t, std::optional<long long> value) {
        const ID3v2::FrameList frames = t->frameList("POPM");
        if (!value) {
            for (auto *frame : frames) {
                auto *p = dynamic_cast<ID3v2::PopularimeterFrame *>(frame);
                if (!p) continue;
                if (p->counter() > 0) p->setRating(0);  // keep the play counter
                else t->removeFrame(p, true);
            }
            return;
        }
        const int popm = popmFromRating(*value);
        bool any = false;
        for (auto *frame : frames) {
            if (auto *p = dynamic_cast<ID3v2::PopularimeterFrame *>(frame)) {
                p->setRating(popm);
                any = true;
            }
        }
        if (!any) {
            auto *p = new ID3v2::PopularimeterFrame();
            p->setEmail(kWMPEmail);
            p->setRating(popm);
            p->setCounter(0);
            t->addFrame(p);
        }
    }

    StringList genres(ID3v2::Tag *t) {
        StringList out;
        for (const auto &raw : textFrame(t, "TCON")) {
            String g = raw.stripWhiteSpace();
            bool numeric = !g.isEmpty();
            for (auto c : g) {
                if (c < '0' || c > '9') {
                    numeric = false;
                    break;
                }
            }
            if (numeric) {
                int n = g.toInt();
                if (n >= 0 && n <= 255) {
                    String name = ID3v1::genre(n);
                    if (!name.isEmpty()) g = name;
                }
            } else if (g == "RX") {
                g = "Remix";
            } else if (g == "CR") {
                g = "Cover";
            }
            out.append(g);
        }
        return dedupe(out);
    }

    Provider provider_;
    int version_;
};

// ------------------------------------------------------------------------------------
// MP4
// ------------------------------------------------------------------------------------

const char *const kMP4Label = "----:com.apple.iTunes:LABEL";
const char *const kMP4ISRC = "----:com.apple.iTunes:ISRC";
const char *const kMP4Rating = "----:com.apple.iTunes:RATING";

class MP4Backend final : public Backend {
public:
    explicit MP4Backend(MP4::Tag *tag) : tag_(tag) {}

    bool supports(TBField f) const override {
        return isTextField(f) || isIntField(f);
    }

    StringList getStrings(TBField f) override {
        if (!tag_) return {};
        for (const auto &key : keys(f)) {
            StringList v = cleaned(strings(key));
            if (!v.isEmpty()) return v;
        }
        return {};
    }

    void setStrings(TBField f, const StringList &rawValues) override {
        if (!tag_ || f == TB_FIELD_DATE) return;
        StringList values = cleaned(rawValues);
        std::vector<String> k = keys(f);
        if (k.empty()) return;
        const String joined = joinValues(values);
        for (size_t i = 0; i < k.size(); ++i) {
            if (joined.isEmpty()) {
                tag_->removeItem(k[i]);
            } else if (i == 0 || tag_->contains(k[i])) {
                tag_->setItem(k[i], MP4::Item(StringList(joined)));
            }
        }
    }

    std::optional<long long> getInt(TBField f) override {
        if (!tag_) return std::nullopt;
        switch (f) {
        case TB_FIELD_YEAR: {
            String d = firstValue(getStrings(TB_FIELD_DATE));
            if (d.isEmpty()) return std::nullopt;
            return yearOfDate(d);
        }
        case TB_FIELD_TRACK_NUMBER:
        case TB_FIELD_TRACK_TOTAL:
        case TB_FIELD_DISC_NUMBER:
        case TB_FIELD_DISC_TOTAL: {
            const bool track = f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_TRACK_TOTAL;
            const char *key = track ? "trkn" : "disk";
            if (!tag_->contains(key)) return std::nullopt;
            MP4::Item::IntPair p = tag_->item(key).toIntPair();
            int v = (f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_DISC_NUMBER) ? p.first : p.second;
            if (v == 0) return std::nullopt;
            return v;
        }
        case TB_FIELD_COMPILATION:
            if (!tag_->contains("cpil")) return std::nullopt;
            return tag_->item("cpil").toBool() ? 1 : 0;
        case TB_FIELD_BPM:
            if (!tag_->contains("tmpo")) return std::nullopt;
            return tag_->item("tmpo").toInt();
        case TB_FIELD_RATING: {
            String r = firstValue(strings(kMP4Rating));
            if (r.isEmpty()) return std::nullopt;
            auto v = leadingInt(r, true);
            if (!v) return std::nullopt;
            return std::max<long long>(0, std::min<long long>(100, *v));
        }
        default: return std::nullopt;
        }
    }

    void setInt(TBField f, std::optional<long long> value) override {
        if (!tag_) return;
        switch (f) {
        case TB_FIELD_YEAR: {
            String current = firstValue(getStrings(TB_FIELD_DATE));
            if (!value) {
                tag_->removeItem("\251day");
                return;
            }
            if (!current.isEmpty() && yearOfDate(current) == value) return;
            tag_->setItem("\251day", MP4::Item(StringList(yearString(*value))));
            return;
        }
        case TB_FIELD_TRACK_NUMBER:
        case TB_FIELD_TRACK_TOTAL:
        case TB_FIELD_DISC_NUMBER:
        case TB_FIELD_DISC_TOTAL: {
            const bool track = f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_TRACK_TOTAL;
            const char *key = track ? "trkn" : "disk";
            MP4::Item::IntPair p{0, 0};
            if (tag_->contains(key)) p = tag_->item(key).toIntPair();
            int v = value ? static_cast<int>(*value) : 0;
            if (f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_DISC_NUMBER) p.first = v;
            else p.second = v;
            if (p.first == 0 && p.second == 0) tag_->removeItem(key);
            else tag_->setItem(key, MP4::Item(p.first, p.second));
            return;
        }
        case TB_FIELD_COMPILATION:
            if (value && *value != 0) tag_->setItem("cpil", MP4::Item(true));
            else tag_->removeItem("cpil");
            return;
        case TB_FIELD_BPM:
            if (value) tag_->setItem("tmpo", MP4::Item(static_cast<int>(*value)));
            else tag_->removeItem("tmpo");
            return;
        case TB_FIELD_RATING:
            if (value) tag_->setItem(kMP4Rating, MP4::Item(StringList(String::number(static_cast<int>(*value)))));
            else tag_->removeItem(kMP4Rating);
            return;
        default: return;
        }
    }

    bool supportsPictures() const override { return true; }

    std::vector<Pic> getPictures() override {
        std::vector<Pic> out;
        if (!tag_ || !tag_->contains("covr")) return out;
        for (const auto &art : tag_->item("covr").toCoverArtList()) {
            Pic p;
            p.type = 3;  // MP4 has no picture types
            p.data = art.data();
            switch (art.format()) {
            case MP4::CoverArt::JPEG: p.mimeType = "image/jpeg"; break;
            case MP4::CoverArt::PNG: p.mimeType = "image/png"; break;
            case MP4::CoverArt::GIF: p.mimeType = "image/gif"; break;
            case MP4::CoverArt::BMP: p.mimeType = "image/bmp"; break;
            default: p.mimeType = sniffImageMime(p.data); break;
            }
            out.push_back(p);
        }
        return out;
    }

    void setPictures(const std::vector<Pic> &pics) override {
        if (!tag_) return;
        if (pics.empty()) {
            tag_->removeItem("covr");
            return;
        }
        MP4::CoverArtList list;
        for (const auto &p : pics) {
            String mime = sniffImageMime(p.data);
            if (mime.isEmpty()) mime = normalizedMime(p.mimeType, p.data);
            MP4::CoverArt::Format format = MP4::CoverArt::Unknown;
            if (mime == "image/jpeg") format = MP4::CoverArt::JPEG;
            else if (mime == "image/png") format = MP4::CoverArt::PNG;
            else if (mime == "image/gif") format = MP4::CoverArt::GIF;
            else if (mime == "image/bmp") format = MP4::CoverArt::BMP;
            list.append(MP4::CoverArt(format, p.data));
        }
        tag_->setItem("covr", MP4::Item(list));
    }

private:
    StringList strings(const String &key) {
        if (!tag_->contains(key)) return {};
        return tag_->item(key).toStringList();
    }

    static std::vector<String> keys(TBField f) {
        switch (f) {
        case TB_FIELD_TITLE: return {"\251nam"};
        case TB_FIELD_ARTISTS: return {"\251ART"};
        case TB_FIELD_ALBUM: return {"\251alb"};
        case TB_FIELD_ALBUM_ARTISTS: return {"aART"};
        case TB_FIELD_COMPOSERS: return {"\251wrt"};
        case TB_FIELD_GROUPING: return {"\251grp"};
        case TB_FIELD_WORK: return {"\251wrk"};
        case TB_FIELD_GENRES: return {"\251gen"};
        case TB_FIELD_COMMENT: return {"\251cmt"};
        case TB_FIELD_LYRICS: return {"\251lyr"};
        case TB_FIELD_TITLE_SORT: return {"sonm"};
        case TB_FIELD_ARTIST_SORT: return {"soar"};
        case TB_FIELD_ALBUM_SORT: return {"soal"};
        case TB_FIELD_ALBUM_ARTIST_SORT: return {"soaa"};
        case TB_FIELD_COMPOSER_SORT: return {"soco"};
        case TB_FIELD_COPYRIGHT: return {"cprt"};
        case TB_FIELD_PUBLISHER: return {kMP4Label, "\251pub"};
        case TB_FIELD_ISRC: return {kMP4ISRC};
        case TB_FIELD_ENCODED_BY: return {"\251enc"};
        case TB_FIELD_DATE: return {"\251day"};
        default: return {};
        }
    }

    MP4::Tag *tag_;
};

// ------------------------------------------------------------------------------------
// Key/value tag formats (Vorbis Comment, APE, ASF, RIFF INFO, generic PropertyMap)
// ------------------------------------------------------------------------------------

struct KVConfig {
    std::map<int, std::vector<String>> keys;  // TBField -> keys (first = written, rest = aliases)
    std::vector<String> trackNumber, trackTotal, discNumber, discTotal;
    bool trackCombined = false;  // "n/t" in trackNumber[0]
    bool discCombined = false;
    enum class Rating { None, Percent, ASF } rating = Rating::None;
};

class KeyValueBackend : public Backend {
public:
    explicit KeyValueBackend(KVConfig config) : cfg_(std::move(config)) {}

    bool supports(TBField f) const override {
        switch (f) {
        case TB_FIELD_YEAR: return cfg_.keys.count(TB_FIELD_DATE) > 0;
        case TB_FIELD_TRACK_NUMBER: return !cfg_.trackNumber.empty();
        case TB_FIELD_TRACK_TOTAL: return cfg_.trackCombined ? !cfg_.trackNumber.empty() : !cfg_.trackTotal.empty();
        case TB_FIELD_DISC_NUMBER: return !cfg_.discNumber.empty();
        case TB_FIELD_DISC_TOTAL: return cfg_.discCombined ? !cfg_.discNumber.empty() : !cfg_.discTotal.empty();
        case TB_FIELD_RATING: return cfg_.rating != KVConfig::Rating::None && cfg_.keys.count(TB_FIELD_RATING) > 0;
        default: return cfg_.keys.count(f) > 0;
        }
    }

    StringList getStrings(TBField f) override {
        auto it = cfg_.keys.find(f);
        if (it == cfg_.keys.end() || !isTextField(f)) return {};
        return firstNonEmpty(it->second);
    }

    void setStrings(TBField f, const StringList &values) override {
        auto it = cfg_.keys.find(f);
        if (it == cfg_.keys.end() || f == TB_FIELD_DATE || !isTextField(f)) return;
        writeAliased(it->second, cleaned(values));
    }

    std::optional<long long> getInt(TBField f) override {
        switch (f) {
        case TB_FIELD_YEAR: {
            String d = firstValue(getStrings(TB_FIELD_DATE));
            if (d.isEmpty()) return std::nullopt;
            return yearOfDate(d);
        }
        case TB_FIELD_TRACK_NUMBER: return pair(true).number;
        case TB_FIELD_TRACK_TOTAL: return pair(true).total;
        case TB_FIELD_DISC_NUMBER: return pair(false).number;
        case TB_FIELD_DISC_TOTAL: return pair(false).total;
        case TB_FIELD_COMPILATION: {
            auto it = cfg_.keys.find(f);
            if (it == cfg_.keys.end()) return std::nullopt;
            StringList v = firstNonEmpty(it->second);
            if (v.isEmpty()) return std::nullopt;
            return truthy(firstValue(v)) ? 1 : 0;
        }
        case TB_FIELD_BPM: {
            auto it = cfg_.keys.find(f);
            if (it == cfg_.keys.end()) return std::nullopt;
            return leadingInt(firstValue(firstNonEmpty(it->second)), true);
        }
        case TB_FIELD_RATING: {
            auto it = cfg_.keys.find(f);
            if (it == cfg_.keys.end()) return std::nullopt;
            auto v = leadingInt(firstValue(firstNonEmpty(it->second)), true);
            if (!v) return std::nullopt;
            if (cfg_.rating == KVConfig::Rating::ASF) return ratingFromAsf(*v);
            return std::max<long long>(0, std::min<long long>(100, *v));
        }
        default: return std::nullopt;
        }
    }

    void setInt(TBField f, std::optional<long long> value) override {
        switch (f) {
        case TB_FIELD_YEAR: {
            auto it = cfg_.keys.find(TB_FIELD_DATE);
            if (it == cfg_.keys.end()) return;
            String current = firstValue(getStrings(TB_FIELD_DATE));
            if (!value) {
                writeAliased(it->second, {});
                return;
            }
            if (!current.isEmpty() && yearOfDate(current) == value) return;
            writeAliased(it->second, StringList(yearString(*value)));
            return;
        }
        case TB_FIELD_TRACK_NUMBER:
        case TB_FIELD_TRACK_TOTAL:
        case TB_FIELD_DISC_NUMBER:
        case TB_FIELD_DISC_TOTAL: {
            const bool track = f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_TRACK_TOTAL;
            NumberPair p = pair(track);
            if (f == TB_FIELD_TRACK_NUMBER || f == TB_FIELD_DISC_NUMBER) p.number = value;
            else p.total = value;
            setPair(track, p);
            return;
        }
        case TB_FIELD_COMPILATION: {
            auto it = cfg_.keys.find(f);
            if (it == cfg_.keys.end()) return;
            writeAliased(it->second, (value && *value != 0) ? StringList("1") : StringList());
            return;
        }
        case TB_FIELD_BPM: {
            auto it = cfg_.keys.find(f);
            if (it == cfg_.keys.end()) return;
            writeAliased(it->second, value ? StringList(String::number(static_cast<int>(*value))) : StringList());
            return;
        }
        case TB_FIELD_RATING: {
            auto it = cfg_.keys.find(f);
            if (it == cfg_.keys.end()) return;
            if (!value) {
                writeAliased(it->second, {});
                return;
            }
            long long stored = cfg_.rating == KVConfig::Rating::ASF ? asfFromRating(*value) : *value;
            writeRating(it->second.front(), stored);
            for (size_t i = 1; i < it->second.size(); ++i) {
                if (has(it->second[i])) writeRating(it->second[i], stored);
            }
            return;
        }
        default: return;
        }
    }

protected:
    // primitives
    virtual bool has(const String &key) = 0;
    virtual StringList get(const String &key) = 0;
    virtual void set(const String &key, const StringList &values) = 0;  // empty = remove
    virtual bool multiValued(const String &) const { return true; }
    virtual void writeRating(const String &key, long long stored) {
        set(key, StringList(String::number(static_cast<int>(stored))));
    }

    StringList firstNonEmpty(const std::vector<String> &keys) {
        for (const auto &k : keys) {
            StringList v = cleaned(get(k));
            if (!v.isEmpty()) return v;
        }
        return {};
    }

    void writeAliased(const std::vector<String> &keys, const StringList &values) {
        for (size_t i = 0; i < keys.size(); ++i) {
            if (values.isEmpty()) {
                if (has(keys[i])) set(keys[i], {});
            } else if (i == 0 || has(keys[i])) {
                set(keys[i], multiValued(keys[i]) ? values : StringList(joinValues(values)));
            }
        }
    }

    NumberPair pair(bool track) {
        const auto &numKeys = track ? cfg_.trackNumber : cfg_.discNumber;
        const auto &totKeys = track ? cfg_.trackTotal : cfg_.discTotal;
        NumberPair p = parsePair(firstValue(firstNonEmpty(numKeys)));
        const bool combined = track ? cfg_.trackCombined : cfg_.discCombined;
        if (!combined && !totKeys.empty()) {
            auto t = leadingInt(firstValue(firstNonEmpty(totKeys)));
            if (t) p.total = t;
        }
        return p;
    }

    void setPair(bool track, const NumberPair &p) {
        const auto &numKeys = track ? cfg_.trackNumber : cfg_.discNumber;
        const auto &totKeys = track ? cfg_.trackTotal : cfg_.discTotal;
        const bool combined = track ? cfg_.trackCombined : cfg_.discCombined;
        if (numKeys.empty()) return;
        if (combined) {
            String s = formatPair(p.number, p.total);
            writeAliased(numKeys, s.isEmpty() ? StringList() : StringList(s));
            return;
        }
        writeAliased(numKeys, p.number ? StringList(String::number(static_cast<int>(*p.number))) : StringList());
        if (!totKeys.empty())
            writeAliased(totKeys, p.total ? StringList(String::number(static_cast<int>(*p.total))) : StringList());
    }

    KVConfig cfg_;
};

// ----- Vorbis Comment (FLAC, Ogg Vorbis/Opus/Speex/FLAC)

KVConfig xiphConfig() {
    KVConfig c;
    c.keys[TB_FIELD_TITLE] = {"TITLE"};
    c.keys[TB_FIELD_ARTISTS] = {"ARTIST"};
    c.keys[TB_FIELD_ALBUM] = {"ALBUM"};
    c.keys[TB_FIELD_ALBUM_ARTISTS] = {"ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST"};
    c.keys[TB_FIELD_COMPOSERS] = {"COMPOSER"};
    c.keys[TB_FIELD_GROUPING] = {"GROUPING"};
    c.keys[TB_FIELD_WORK] = {"WORK"};
    c.keys[TB_FIELD_GENRES] = {"GENRE"};
    c.keys[TB_FIELD_COMMENT] = {"COMMENT", "DESCRIPTION"};
    c.keys[TB_FIELD_LYRICS] = {"LYRICS", "UNSYNCEDLYRICS"};
    c.keys[TB_FIELD_TITLE_SORT] = {"TITLESORT"};
    c.keys[TB_FIELD_ARTIST_SORT] = {"ARTISTSORT"};
    c.keys[TB_FIELD_ALBUM_SORT] = {"ALBUMSORT"};
    c.keys[TB_FIELD_ALBUM_ARTIST_SORT] = {"ALBUMARTISTSORT"};
    c.keys[TB_FIELD_COMPOSER_SORT] = {"COMPOSERSORT"};
    c.keys[TB_FIELD_COPYRIGHT] = {"COPYRIGHT"};
    c.keys[TB_FIELD_PUBLISHER] = {"LABEL", "ORGANIZATION", "PUBLISHER"};
    c.keys[TB_FIELD_ISRC] = {"ISRC"};
    c.keys[TB_FIELD_ENCODED_BY] = {"ENCODEDBY", "ENCODED-BY"};
    c.keys[TB_FIELD_DATE] = {"DATE", "YEAR"};
    c.keys[TB_FIELD_COMPILATION] = {"COMPILATION"};
    c.keys[TB_FIELD_RATING] = {"RATING"};
    c.keys[TB_FIELD_BPM] = {"BPM"};
    c.trackNumber = {"TRACKNUMBER"};
    c.trackTotal = {"TRACKTOTAL", "TOTALTRACKS"};
    c.discNumber = {"DISCNUMBER"};
    c.discTotal = {"DISCTOTAL", "TOTALDISCS"};
    c.rating = KVConfig::Rating::Percent;
    return c;
}

class XiphBackend final : public KeyValueBackend {
public:
    using Provider = std::function<Ogg::XiphComment *(bool create)>;

    XiphBackend(Provider provider, FLAC::File *flac)
        : KeyValueBackend(xiphConfig()), provider_(std::move(provider)), flac_(flac) {}

    std::optional<long long> getInt(TBField f) override {
        auto v = KeyValueBackend::getInt(f);
        if (f == TB_FIELD_RATING && !v) {
            // FMPS_RATING: 0.0 ... 1.0
            String fmps = firstValue(get("FMPS_RATING"));
            if (!fmps.isEmpty()) {
                double d = std::atof(toUTF8(fmps).c_str());
                if (d >= 0 && d <= 1) return static_cast<long long>(d * 100 + 0.5);
            }
        }
        return v;
    }

    void setInt(TBField f, std::optional<long long> value) override {
        KeyValueBackend::setInt(f, value);
        if (f == TB_FIELD_RATING && has("FMPS_RATING")) {
            if (!value) {
                set("FMPS_RATING", {});
            } else {
                char buf[16];
                std::snprintf(buf, sizeof buf, "%.2f", static_cast<double>(*value) / 100.0);
                set("FMPS_RATING", StringList(String(buf)));
            }
        }
    }

    bool supportsPictures() const override { return true; }

    std::vector<Pic> getPictures() override {
        std::vector<Pic> out;
        List<FLAC::Picture *> list;
        if (flac_) list = flac_->pictureList();
        if (list.isEmpty()) {
            if (Ogg::XiphComment *x = provider_(false)) list = x->pictureList();
        }
        for (auto *fp : list) {
            Pic p;
            p.type = clampPictureType(static_cast<int>(fp->type()));
            p.mimeType = normalizedMime(fp->mimeType(), fp->data());
            p.description = fp->description();
            p.data = fp->data();
            p.width = fp->width();
            p.height = fp->height();
            p.colorDepth = fp->colorDepth();
            p.numColors = fp->numColors();
            out.push_back(p);
        }
        return out;
    }

    void setPictures(const std::vector<Pic> &pics) override {
        Ogg::XiphComment *x = provider_(flac_ == nullptr);
        if (flac_) {
            flac_->removePictures();
            if (x) x->removeAllPictures();  // stale METADATA_BLOCK_PICTURE fields inside a FLAC comment
        } else if (x) {
            x->removeAllPictures();
        }
        for (const auto &p : pics) {
            auto *fp = new FLAC::Picture();
            fp->setType(static_cast<FLAC::Picture::Type>(clampPictureType(p.type)));
            fp->setMimeType(p.mimeType.isEmpty() ? sniffImageMime(p.data) : p.mimeType);
            fp->setDescription(p.description);
            fp->setData(p.data);
            fp->setWidth(p.width);
            fp->setHeight(p.height);
            fp->setColorDepth(p.colorDepth);
            fp->setNumColors(p.numColors);
            if (flac_) flac_->addPicture(fp);
            else if (x) x->addPicture(fp);
            else delete fp;
        }
    }

protected:
    bool has(const String &key) override {
        Ogg::XiphComment *x = provider_(false);
        return x && x->contains(key);
    }
    StringList get(const String &key) override {
        Ogg::XiphComment *x = provider_(false);
        if (!x) return {};
        const auto &map = x->fieldListMap();
        auto it = map.find(key.upper());
        return it == map.end() ? StringList() : it->second;
    }
    void set(const String &key, const StringList &values) override {
        Ogg::XiphComment *x = provider_(!values.isEmpty());
        if (!x) return;
        x->removeFields(key.upper());
        for (const auto &v : values) x->addField(key.upper(), v, false);
    }

private:
    Provider provider_;
    FLAC::File *flac_;
};

// ----- APEv2

KVConfig apeConfig() {
    KVConfig c;
    c.keys[TB_FIELD_TITLE] = {"Title"};
    c.keys[TB_FIELD_ARTISTS] = {"Artist"};
    c.keys[TB_FIELD_ALBUM] = {"Album"};
    c.keys[TB_FIELD_ALBUM_ARTISTS] = {"Album Artist", "AlbumArtist", "Album_Artist"};
    c.keys[TB_FIELD_COMPOSERS] = {"Composer"};
    c.keys[TB_FIELD_GROUPING] = {"Grouping"};
    c.keys[TB_FIELD_WORK] = {"Work"};
    c.keys[TB_FIELD_GENRES] = {"Genre"};
    c.keys[TB_FIELD_COMMENT] = {"Comment"};
    c.keys[TB_FIELD_LYRICS] = {"Lyrics", "UnsyncedLyrics"};
    c.keys[TB_FIELD_TITLE_SORT] = {"TITLESORT"};
    c.keys[TB_FIELD_ARTIST_SORT] = {"ARTISTSORT"};
    c.keys[TB_FIELD_ALBUM_SORT] = {"ALBUMSORT"};
    c.keys[TB_FIELD_ALBUM_ARTIST_SORT] = {"ALBUMARTISTSORT"};
    c.keys[TB_FIELD_COMPOSER_SORT] = {"COMPOSERSORT"};
    c.keys[TB_FIELD_COPYRIGHT] = {"Copyright"};
    c.keys[TB_FIELD_PUBLISHER] = {"Label", "Publisher"};
    c.keys[TB_FIELD_ISRC] = {"ISRC"};
    c.keys[TB_FIELD_ENCODED_BY] = {"EncodedBy", "Encoded By"};
    c.keys[TB_FIELD_DATE] = {"Year", "Date"};
    c.keys[TB_FIELD_COMPILATION] = {"Compilation"};
    c.keys[TB_FIELD_RATING] = {"Rating"};
    c.keys[TB_FIELD_BPM] = {"BPM"};
    c.trackNumber = {"Track"};
    c.discNumber = {"Disc"};
    c.trackCombined = true;
    c.discCombined = true;
    c.rating = KVConfig::Rating::Percent;
    return c;
}

const char *const kAPEPictureKeys[21] = {
    "Cover Art (Other)",      "Cover Art (Icon)",        "Cover Art (Other Icon)",
    "Cover Art (Front)",      "Cover Art (Back)",        "Cover Art (Leaflet)",
    "Cover Art (Media)",      "Cover Art (Lead)",        "Cover Art (Artist)",
    "Cover Art (Conductor)",  "Cover Art (Band)",        "Cover Art (Composer)",
    "Cover Art (Lyricist)",   "Cover Art (Studio)",      "Cover Art (Recording)",
    "Cover Art (Performance)", "Cover Art (Movie Scene)", "Cover Art (Colored Fish)",
    "Cover Art (Illustration)", "Cover Art (Band Logo)",  "Cover Art (Publisher Logo)"};

class APEBackend final : public KeyValueBackend {
public:
    using Provider = std::function<APE::Tag *(bool create)>;

    APEBackend(Provider provider, bool primary)
        : KeyValueBackend(apeConfig()), provider_(std::move(provider)), primary_(primary) {}

    bool supportsPictures() const override { return primary_; }

    std::vector<Pic> getPictures() override {
        std::vector<Pic> out;
        APE::Tag *t = provider_(false);
        if (!t) return out;
        const auto &map = t->itemListMap();
        for (int type = 0; type <= 20; ++type) {
            auto it = map.find(String(kAPEPictureKeys[type]).upper());
            if (it == map.end() || it->second.type() != APE::Item::Binary) continue;
            ByteVector data = it->second.binaryData();
            String description;
            // "<description>\0<image data>" (description is usually a file name)
            int nul = data.find(ByteVector("\0", 1));
            if (nul >= 0 && nul < 1024 && !sniffImageMime(data.mid(static_cast<unsigned int>(nul) + 1)).isEmpty()) {
                description = String(data.mid(0, static_cast<unsigned int>(nul)), String::UTF8);
                data = data.mid(static_cast<unsigned int>(nul) + 1);
            }
            Pic p;
            p.type = type;
            p.description = description;
            p.data = data;
            p.mimeType = sniffImageMime(data);
            out.push_back(p);
        }
        return out;
    }

    void setPictures(const std::vector<Pic> &pics) override {
        APE::Tag *t = provider_(true);
        for (const char *key : kAPEPictureKeys) t->removeItem(key);
        std::set<int> used;
        for (const auto &p : pics) {
            int type = clampPictureType(p.type);
            if (used.count(type)) continue;  // APE: one picture per type
            used.insert(type);
            ByteVector data = p.description.data(String::UTF8);
            data.append('\0');
            data.append(p.data);
            APE::Item item(kAPEPictureKeys[type], data, true);
            t->setItem(kAPEPictureKeys[type], item);
        }
    }

protected:
    bool has(const String &key) override {
        APE::Tag *t = provider_(false);
        return t && t->itemListMap().contains(key.upper());
    }
    StringList get(const String &key) override {
        APE::Tag *t = provider_(false);
        if (!t) return {};
        const auto &map = t->itemListMap();
        auto it = map.find(key.upper());
        if (it == map.end() || it->second.type() != APE::Item::Text) return {};
        return it->second.values();
    }
    void set(const String &key, const StringList &values) override {
        APE::Tag *t = provider_(!values.isEmpty());
        if (!t) return;
        if (values.isEmpty()) {
            t->removeItem(key);
            return;
        }
        // keep the spelling of an existing key
        String spelled = key;
        auto it = t->itemListMap().find(key.upper());
        if (it != t->itemListMap().end()) spelled = it->second.key();
        t->setItem(spelled, APE::Item(spelled, values));
    }

private:
    Provider provider_;
    bool primary_;
};

// ----- ASF (WMA)

KVConfig asfConfig() {
    KVConfig c;
    c.keys[TB_FIELD_TITLE] = {"#TITLE"};
    c.keys[TB_FIELD_ARTISTS] = {"#ARTIST"};
    c.keys[TB_FIELD_ALBUM] = {"WM/AlbumTitle"};
    c.keys[TB_FIELD_ALBUM_ARTISTS] = {"WM/AlbumArtist"};
    c.keys[TB_FIELD_COMPOSERS] = {"WM/Composer"};
    c.keys[TB_FIELD_GROUPING] = {"WM/ContentGroupDescription"};
    c.keys[TB_FIELD_GENRES] = {"WM/Genre"};
    c.keys[TB_FIELD_COMMENT] = {"#COMMENT", "Description"};  // ffmpeg writes an attribute "Description"
    c.keys[TB_FIELD_LYRICS] = {"WM/Lyrics"};
    c.keys[TB_FIELD_TITLE_SORT] = {"WM/TitleSortOrder"};
    c.keys[TB_FIELD_ARTIST_SORT] = {"WM/ArtistSortOrder"};
    c.keys[TB_FIELD_ALBUM_SORT] = {"WM/AlbumSortOrder"};
    c.keys[TB_FIELD_ALBUM_ARTIST_SORT] = {"WM/AlbumArtistSortOrder"};
    c.keys[TB_FIELD_COPYRIGHT] = {"#COPYRIGHT"};
    c.keys[TB_FIELD_PUBLISHER] = {"WM/Publisher"};
    c.keys[TB_FIELD_ISRC] = {"WM/ISRC"};
    c.keys[TB_FIELD_ENCODED_BY] = {"WM/EncodedBy"};
    c.keys[TB_FIELD_DATE] = {"WM/Year"};
    c.keys[TB_FIELD_RATING] = {"WM/SharedUserRating"};
    c.keys[TB_FIELD_BPM] = {"WM/BeatsPerMinute"};
    c.trackNumber = {"WM/TrackNumber"};
    c.discNumber = {"WM/PartOfSet"};
    c.discCombined = true;
    c.rating = KVConfig::Rating::ASF;
    return c;
}

class ASFBackend final : public KeyValueBackend {
public:
    explicit ASFBackend(ASF::Tag *tag) : KeyValueBackend(asfConfig()), tag_(tag) {}

    bool supportsPictures() const override { return true; }

    std::vector<Pic> getPictures() override {
        std::vector<Pic> out;
        if (!tag_ || !tag_->contains("WM/Picture")) return out;
        for (const auto &attr : tag_->attribute("WM/Picture")) {
            ASF::Picture pic = attr.toPicture();
            if (!pic.isValid()) continue;
            Pic p;
            p.type = clampPictureType(static_cast<int>(pic.type()));
            p.mimeType = normalizedMime(pic.mimeType(), pic.picture());
            p.description = pic.description();
            p.data = pic.picture();
            out.push_back(p);
        }
        return out;
    }

    void setPictures(const std::vector<Pic> &pics) override {
        if (!tag_) return;
        tag_->removeItem("WM/Picture");
        for (const auto &p : pics) {
            ASF::Picture pic;
            pic.setType(static_cast<ASF::Picture::Type>(clampPictureType(p.type)));
            pic.setMimeType(p.mimeType.isEmpty() ? sniffImageMime(p.data) : p.mimeType);
            pic.setDescription(p.description);
            pic.setPicture(p.data);
            tag_->addAttribute("WM/Picture", ASF::Attribute(pic));
        }
    }

protected:
    bool has(const String &key) override {
        if (!tag_) return false;
        if (key.startsWith("#")) return !get(key).isEmpty();
        return tag_->contains(key);
    }
    StringList get(const String &key) override {
        if (!tag_) return {};
        if (key == "#TITLE") return StringList(tag_->title());
        if (key == "#ARTIST") return StringList(tag_->artist());
        if (key == "#COMMENT") return StringList(tag_->comment());
        if (key == "#COPYRIGHT") return StringList(tag_->copyright());
        StringList out;
        if (!tag_->contains(key)) return out;
        for (const auto &a : tag_->attribute(key)) {
            switch (a.type()) {
            case ASF::Attribute::UnicodeType: out.append(a.toString()); break;
            case ASF::Attribute::DWordType: out.append(String::number(static_cast<int>(a.toUInt()))); break;
            case ASF::Attribute::QWordType: out.append(String::number(static_cast<long long>(a.toULongLong()))); break;
            case ASF::Attribute::WordType: out.append(String::number(static_cast<int>(a.toUShort()))); break;
            case ASF::Attribute::BoolType: out.append(a.toBool() ? "1" : "0"); break;
            default: break;
            }
        }
        return out;
    }
    void set(const String &key, const StringList &values) override {
        if (!tag_) return;
        const String joined = joinValues(values);
        if (key == "#TITLE") { tag_->setTitle(joined); return; }
        if (key == "#ARTIST") { tag_->setArtist(joined); return; }
        if (key == "#COMMENT") { tag_->setComment(joined); return; }
        if (key == "#COPYRIGHT") { tag_->setCopyright(joined); return; }
        tag_->removeItem(key);
        for (const auto &v : values) tag_->addAttribute(key, ASF::Attribute(v));
    }
    // TagLib stores the 2nd+ value of an attribute in the Metadata Library object, so the order of
    // repeated attributes is not stable across a save: store multiple values joined in one attribute.
    bool multiValued(const String &) const override { return false; }
    void writeRating(const String &key, long long stored) override {
        if (!tag_) return;
        tag_->removeItem(key);
        tag_->addAttribute(key, ASF::Attribute(static_cast<unsigned int>(stored)));
    }

private:
    ASF::Tag *tag_;
};

// ----- RIFF INFO (secondary tag of WAV)

KVConfig infoConfig() {
    KVConfig c;
    c.keys[TB_FIELD_TITLE] = {"INAM"};
    c.keys[TB_FIELD_ARTISTS] = {"IART"};
    c.keys[TB_FIELD_ALBUM] = {"IPRD"};
    c.keys[TB_FIELD_COMPOSERS] = {"IMUS"};
    c.keys[TB_FIELD_GENRES] = {"IGNR"};
    c.keys[TB_FIELD_COMMENT] = {"ICMT"};
    c.keys[TB_FIELD_COPYRIGHT] = {"ICOP"};
    c.keys[TB_FIELD_DATE] = {"ICRD"};
    c.trackNumber = {"IPRT", "ITRK"};
    return c;
}

class InfoBackend final : public KeyValueBackend {
public:
    explicit InfoBackend(RIFF::Info::Tag *tag) : KeyValueBackend(infoConfig()), tag_(tag) {}

protected:
    bool has(const String &key) override {
        return tag_ && !tag_->fieldText(key.data(String::Latin1)).isEmpty();
    }
    StringList get(const String &key) override {
        if (!tag_) return {};
        String v = tag_->fieldText(key.data(String::Latin1));
        return v.isEmpty() ? StringList() : StringList(v);
    }
    void set(const String &key, const StringList &values) override {
        if (!tag_) return;
        const String joined = joinValues(values);
        if (joined.isEmpty()) tag_->removeField(key.data(String::Latin1));
        else tag_->setFieldText(key.data(String::Latin1), joined);
    }
    bool multiValued(const String &) const override { return false; }

private:
    RIFF::Info::Tag *tag_;
};

// ----- Generic PropertyMap backend (Matroska, Shorten, modules, DIIN ...)

KVConfig propertyConfig() {
    KVConfig c;
    c.keys[TB_FIELD_TITLE] = {"TITLE"};
    c.keys[TB_FIELD_ARTISTS] = {"ARTIST"};
    c.keys[TB_FIELD_ALBUM] = {"ALBUM"};
    c.keys[TB_FIELD_ALBUM_ARTISTS] = {"ALBUMARTIST"};
    c.keys[TB_FIELD_COMPOSERS] = {"COMPOSER"};
    c.keys[TB_FIELD_GROUPING] = {"GROUPING"};
    c.keys[TB_FIELD_WORK] = {"WORK"};
    c.keys[TB_FIELD_GENRES] = {"GENRE"};
    c.keys[TB_FIELD_COMMENT] = {"COMMENT"};
    c.keys[TB_FIELD_LYRICS] = {"LYRICS"};
    c.keys[TB_FIELD_TITLE_SORT] = {"TITLESORT"};
    c.keys[TB_FIELD_ARTIST_SORT] = {"ARTISTSORT"};
    c.keys[TB_FIELD_ALBUM_SORT] = {"ALBUMSORT"};
    c.keys[TB_FIELD_ALBUM_ARTIST_SORT] = {"ALBUMARTISTSORT"};
    c.keys[TB_FIELD_COMPOSER_SORT] = {"COMPOSERSORT"};
    c.keys[TB_FIELD_COPYRIGHT] = {"COPYRIGHT"};
    c.keys[TB_FIELD_PUBLISHER] = {"LABEL"};
    c.keys[TB_FIELD_ISRC] = {"ISRC"};
    c.keys[TB_FIELD_ENCODED_BY] = {"ENCODEDBY"};
    c.keys[TB_FIELD_DATE] = {"DATE"};
    c.keys[TB_FIELD_COMPILATION] = {"COMPILATION"};
    c.keys[TB_FIELD_RATING] = {"RATING"};
    c.keys[TB_FIELD_BPM] = {"BPM"};
    c.trackNumber = {"TRACKNUMBER"};
    c.trackTotal = {"TRACKTOTAL"};
    c.discNumber = {"DISCNUMBER"};
    c.discTotal = {"DISCTOTAL"};
    c.rating = KVConfig::Rating::Percent;
    return c;
}

class PropertyBackend final : public KeyValueBackend {
public:
    // `target` is either a TagLib::File or a TagLib::Tag (exactly one non-null).
    PropertyBackend(TagLib::File *file, TagLib::Tag *tag, KVConfig cfg)
        : KeyValueBackend(std::move(cfg)), file_(file), tag_(tag) {}

    bool supportsPictures() const override {
        return file_ && file_->complexPropertyKeys().contains("PICTURE");
    }

    std::vector<Pic> getPictures() override {
        std::vector<Pic> out;
        if (!file_) return out;
        for (const auto &m : file_->complexProperties("PICTURE")) {
            Pic p;
            p.data = m.value("data").value<ByteVector>();
            p.mimeType = normalizedMime(m.value("mimeType").value<String>(), p.data);
            p.description = m.value("description").value<String>();
            String typeName = m.value("pictureType").value<String>();
            p.type = typeName.isEmpty() ? 3 : clampPictureType(Utils::pictureTypeFromString(typeName));
            out.push_back(p);
        }
        return out;
    }

    void setPictures(const std::vector<Pic> &pics) override {
        if (!file_) return;
        List<VariantMap> list;
        for (const auto &p : pics) {
            VariantMap m;
            m.insert("data", p.data);
            m.insert("mimeType", p.mimeType);
            m.insert("description", p.description);
            m.insert("pictureType", Utils::pictureTypeToString(clampPictureType(p.type)));
            list.append(m);
        }
        file_->setComplexProperties("PICTURE", list);
    }

protected:
    PropertyMap props() const { return file_ ? file_->properties() : tag_->properties(); }
    void apply(const PropertyMap &m) {
        if (file_) file_->setProperties(m);
        else tag_->setProperties(m);
    }
    bool has(const String &key) override { return props().contains(key.upper()); }
    StringList get(const String &key) override {
        PropertyMap m = props();
        auto it = m.find(key.upper());
        return it == m.end() ? StringList() : it->second;
    }
    void set(const String &key, const StringList &values) override {
        PropertyMap m = props();
        if (values.isEmpty()) m.erase(key.upper());
        else m.replace(key.upper(), values);
        apply(m);
    }

private:
    TagLib::File *file_;
    TagLib::Tag *tag_;
};

// ----- Basic TagLib::Tag (ID3v1 as secondary tag)

class BasicBackend final : public Backend {
public:
    using Provider = std::function<TagLib::Tag *(bool create)>;
    explicit BasicBackend(Provider provider) : provider_(std::move(provider)) {}

    bool supports(TBField f) const override {
        switch (f) {
        case TB_FIELD_TITLE: case TB_FIELD_ARTISTS: case TB_FIELD_ALBUM: case TB_FIELD_COMMENT:
        case TB_FIELD_GENRES: case TB_FIELD_YEAR: case TB_FIELD_TRACK_NUMBER: case TB_FIELD_DATE:
            return true;
        default: return false;
        }
    }
    StringList getStrings(TBField f) override {
        TagLib::Tag *t = provider_(false);
        if (!t) return {};
        String v;
        switch (f) {
        case TB_FIELD_TITLE: v = t->title(); break;
        case TB_FIELD_ARTISTS: v = t->artist(); break;
        case TB_FIELD_ALBUM: v = t->album(); break;
        case TB_FIELD_COMMENT: v = t->comment(); break;
        case TB_FIELD_GENRES: v = t->genre(); break;
        case TB_FIELD_DATE: if (t->year() > 0) v = String::number(static_cast<int>(t->year())); break;
        default: break;
        }
        v = v.stripWhiteSpace();
        return v.isEmpty() ? StringList() : StringList(v);
    }
    void setStrings(TBField f, const StringList &values) override {
        TagLib::Tag *t = provider_(false);
        if (!t) return;
        const String joined = joinValues(values);
        switch (f) {
        case TB_FIELD_TITLE: t->setTitle(joined); break;
        case TB_FIELD_ARTISTS: t->setArtist(joined); break;
        case TB_FIELD_ALBUM: t->setAlbum(joined); break;
        case TB_FIELD_COMMENT: t->setComment(joined); break;
        case TB_FIELD_GENRES: t->setGenre(firstValue(cleaned(values))); break;
        default: break;
        }
    }
    std::optional<long long> getInt(TBField f) override {
        TagLib::Tag *t = provider_(false);
        if (!t) return std::nullopt;
        if (f == TB_FIELD_YEAR && t->year() > 0) return t->year();
        if (f == TB_FIELD_TRACK_NUMBER && t->track() > 0) return t->track();
        return std::nullopt;
    }
    void setInt(TBField f, std::optional<long long> value) override {
        TagLib::Tag *t = provider_(false);
        if (!t) return;
        unsigned int v = (value && *value > 0) ? static_cast<unsigned int>(*value) : 0;
        if (f == TB_FIELD_YEAR) t->setYear(v);
        if (f == TB_FIELD_TRACK_NUMBER) t->setTrack(v);
    }

private:
    Provider provider_;
};

// ----- DSDIFF DIIN (title and artist only)

class DIINBackend final : public Backend {
public:
    explicit DIINBackend(DSDIFF::DIIN::Tag *tag) : tag_(tag) {}
    bool supports(TBField f) const override { return f == TB_FIELD_TITLE || f == TB_FIELD_ARTISTS; }
    StringList getStrings(TBField f) override {
        if (!tag_) return {};
        String v = f == TB_FIELD_TITLE ? tag_->title() : (f == TB_FIELD_ARTISTS ? tag_->artist() : String());
        return v.isEmpty() ? StringList() : StringList(v);
    }
    void setStrings(TBField f, const StringList &values) override {
        if (!tag_) return;
        if (f == TB_FIELD_TITLE) tag_->setTitle(joinValues(values));
        if (f == TB_FIELD_ARTISTS) tag_->setArtist(joinValues(values));
    }
    std::optional<long long> getInt(TBField) override { return std::nullopt; }
    void setInt(TBField, std::optional<long long>) override {}

private:
    DSDIFF::DIIN::Tag *tag_;
};

// ====================================================================================
// File detection
// ====================================================================================

TBFileType sniffType(IOStream *stream) {
    stream->seek(0);
    ByteVector head = stream->readBlock(64);
    if (head.size() >= 10 && head.startsWith("ID3")) {
        const unsigned char *b = reinterpret_cast<const unsigned char *>(head.data());
        offset_t size = (static_cast<offset_t>(b[6] & 0x7f) << 21) | ((b[7] & 0x7f) << 14) |
                        ((b[8] & 0x7f) << 7) | (b[9] & 0x7f);
        offset_t offset = 10 + size + ((b[5] & 0x10) ? 10 : 0);
        stream->seek(offset);
        head = stream->readBlock(64);
    }
    stream->seek(0);
    if (head.size() < 12) return TB_FILE_UNKNOWN;
    const unsigned char *b = reinterpret_cast<const unsigned char *>(head.data());
    if (head.startsWith("fLaC")) return TB_FILE_FLAC;
    if (head.startsWith("OggS")) {
        const unsigned int segments = b[26];
        const unsigned int start = 27 + segments;
        if (head.size() >= start + 8) {
            ByteVector packet = head.mid(start, 8);
            if (packet.startsWith("\x01vorbis")) return TB_FILE_OGG_VORBIS;
            if (packet.startsWith("OpusHead")) return TB_FILE_OGG_OPUS;
            if (packet.startsWith("Speex   ")) return TB_FILE_OGG_SPEEX;
            if (packet.startsWith("\x7f" "FLAC")) return TB_FILE_OGG_FLAC;
            if (packet.startsWith("fLaC")) return TB_FILE_OGG_FLAC;  // old Ogg FLAC mapping
        }
        return TB_FILE_UNKNOWN;
    }
    if (head.mid(4, 4) == "ftyp") return TB_FILE_MP4;
    if (head.startsWith("RIFF") && head.mid(8, 4) == "WAVE") return TB_FILE_WAV;
    if (head.startsWith("FORM") && (head.mid(8, 4) == "AIFF" || head.mid(8, 4) == "AIFC")) return TB_FILE_AIFF;
    if (head.startsWith("MAC ")) return TB_FILE_APE;
    if (head.startsWith("wvpk")) return TB_FILE_WAVPACK;
    if (head.startsWith("MPCK") || head.startsWith("MP+")) return TB_FILE_MPC;
    if (head.startsWith("TTA1")) return TB_FILE_TRUEAUDIO;
    static const unsigned char asfGuid[16] = {0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11,
                                              0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C};
    if (head.size() >= 16 && std::memcmp(b, asfGuid, 16) == 0) return TB_FILE_ASF;
    if (head.startsWith("DSD ")) return TB_FILE_DSF;
    if (head.startsWith("FRM8")) return TB_FILE_DSDIFF;
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) return TB_FILE_MATROSKA;
    if (head.startsWith("ajkg")) return TB_FILE_SHORTEN;
    if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return TB_FILE_MPEG;
    return TB_FILE_UNKNOWN;
}

TBFileType typeFromExtension(const std::string &path) {
    size_t dot = path.rfind('.');
    size_t slash = path.rfind('/');
    if (dot == std::string::npos || (slash != std::string::npos && dot < slash)) return TB_FILE_UNKNOWN;
    std::string ext = path.substr(dot + 1);
    for (auto &c : ext) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    if (ext == "MP3" || ext == "MP2" || ext == "MP1" || ext == "AAC") return TB_FILE_MPEG;
    if (ext == "M4A" || ext == "M4B" || ext == "M4P" || ext == "M4R" || ext == "MP4" || ext == "3G2" || ext == "M4V")
        return TB_FILE_MP4;
    if (ext == "FLAC") return TB_FILE_FLAC;
    if (ext == "OGG") return TB_FILE_OGG_VORBIS;
    if (ext == "OPUS") return TB_FILE_OGG_OPUS;
    if (ext == "SPX") return TB_FILE_OGG_SPEEX;
    if (ext == "OGA") return TB_FILE_OGG_FLAC;
    if (ext == "WAV") return TB_FILE_WAV;
    if (ext == "AIF" || ext == "AIFF" || ext == "AIFC" || ext == "AFC") return TB_FILE_AIFF;
    if (ext == "APE") return TB_FILE_APE;
    if (ext == "WV") return TB_FILE_WAVPACK;
    if (ext == "MPC") return TB_FILE_MPC;
    if (ext == "WMA" || ext == "ASF") return TB_FILE_ASF;
    if (ext == "DSF") return TB_FILE_DSF;
    if (ext == "DFF" || ext == "DSDIFF") return TB_FILE_DSDIFF;
    if (ext == "TTA") return TB_FILE_TRUEAUDIO;
    if (ext == "MKA" || ext == "MKV" || ext == "WEBM") return TB_FILE_MATROSKA;
    if (ext == "SHN") return TB_FILE_SHORTEN;
    if (ext == "MOD" || ext == "MODULE" || ext == "NST" || ext == "WOW" || ext == "S3M" || ext == "IT" || ext == "XM")
        return TB_FILE_MOD;
    return TB_FILE_UNKNOWN;
}

std::unique_ptr<TagLib::File> createFile(TBFileType type, IOStream *s, const std::string &path, bool props,
                                         AudioProperties::ReadStyle style) {
    switch (type) {
    case TB_FILE_MPEG: return std::make_unique<MPEG::File>(s, props, style);
    case TB_FILE_MP4: return std::make_unique<MP4::File>(s, props, style);
    case TB_FILE_FLAC: return std::make_unique<FLAC::File>(s, props, style);
    case TB_FILE_OGG_VORBIS: return std::make_unique<Ogg::Vorbis::File>(s, props, style);
    case TB_FILE_OGG_OPUS: return std::make_unique<Ogg::Opus::File>(s, props, style);
    case TB_FILE_OGG_SPEEX: return std::make_unique<Ogg::Speex::File>(s, props, style);
    case TB_FILE_OGG_FLAC: return std::make_unique<Ogg::FLAC::File>(s, props, style);
    case TB_FILE_WAV: return std::make_unique<RIFF::WAV::File>(s, props, style);
    case TB_FILE_AIFF: return std::make_unique<RIFF::AIFF::File>(s, props, style);
    case TB_FILE_APE: return std::make_unique<APE::File>(s, props, style);
    case TB_FILE_WAVPACK: return std::make_unique<WavPack::File>(s, props, style);
    case TB_FILE_MPC: return std::make_unique<MPC::File>(s, props, style);
    case TB_FILE_ASF: return std::make_unique<ASF::File>(s, props, style);
    case TB_FILE_DSF: return std::make_unique<DSF::File>(s, props, style);
    case TB_FILE_DSDIFF: return std::make_unique<DSDIFF::File>(s, props, style);
    case TB_FILE_TRUEAUDIO: return std::make_unique<TrueAudio::File>(s, props, style);
    case TB_FILE_MATROSKA: return std::make_unique<Matroska::File>(s, props, style);
    case TB_FILE_SHORTEN: return std::make_unique<Shorten::File>(s, props, style);
    case TB_FILE_MOD: {
        std::string ext = path.substr(path.rfind('.') == std::string::npos ? path.size() : path.rfind('.') + 1);
        for (auto &c : ext) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if (ext == "S3M") return std::make_unique<S3M::File>(s, props, style);
        if (ext == "IT") return std::make_unique<IT::File>(s, props, style);
        if (ext == "XM") return std::make_unique<XM::File>(s, props, style);
        return std::make_unique<Mod::File>(s, props, style);
    }
    default: return nullptr;
    }
}

/// Content-based detection like TagLib's FileRef (used when neither magic nor extension decide).
TBFileType detectByContent(IOStream *s) {
    if (Ogg::Vorbis::File::isSupported(s)) return TB_FILE_OGG_VORBIS;
    if (Ogg::FLAC::File::isSupported(s)) return TB_FILE_OGG_FLAC;
    if (FLAC::File::isSupported(s)) return TB_FILE_FLAC;
    if (Ogg::Speex::File::isSupported(s)) return TB_FILE_OGG_SPEEX;
    if (Ogg::Opus::File::isSupported(s)) return TB_FILE_OGG_OPUS;
    if (MPC::File::isSupported(s)) return TB_FILE_MPC;
    if (WavPack::File::isSupported(s)) return TB_FILE_WAVPACK;
    if (APE::File::isSupported(s)) return TB_FILE_APE;
    if (TrueAudio::File::isSupported(s)) return TB_FILE_TRUEAUDIO;
    if (MP4::File::isSupported(s)) return TB_FILE_MP4;
    if (ASF::File::isSupported(s)) return TB_FILE_ASF;
    if (RIFF::AIFF::File::isSupported(s)) return TB_FILE_AIFF;
    if (RIFF::WAV::File::isSupported(s)) return TB_FILE_WAV;
    if (DSF::File::isSupported(s)) return TB_FILE_DSF;
    if (DSDIFF::File::isSupported(s)) return TB_FILE_DSDIFF;
    if (Shorten::File::isSupported(s)) return TB_FILE_SHORTEN;
    if (Matroska::File::isSupported(s)) return TB_FILE_MATROSKA;
    if (MPEG::File::isSupported(s)) return TB_FILE_MPEG;
    return TB_FILE_UNKNOWN;
}

const char *formatName(TBFileType t) {
    switch (t) {
    case TB_FILE_MPEG: return "MP3";
    case TB_FILE_MP4: return "MPEG-4 Audio";
    case TB_FILE_FLAC: return "FLAC";
    case TB_FILE_OGG_VORBIS: return "Ogg Vorbis";
    case TB_FILE_OGG_OPUS: return "Ogg Opus";
    case TB_FILE_OGG_SPEEX: return "Ogg Speex";
    case TB_FILE_OGG_FLAC: return "Ogg FLAC";
    case TB_FILE_WAV: return "WAV";
    case TB_FILE_AIFF: return "AIFF";
    case TB_FILE_APE: return "Monkey's Audio";
    case TB_FILE_WAVPACK: return "WavPack";
    case TB_FILE_MPC: return "Musepack";
    case TB_FILE_ASF: return "Windows Media Audio";
    case TB_FILE_DSF: return "DSF";
    case TB_FILE_DSDIFF: return "DSDIFF";
    case TB_FILE_TRUEAUDIO: return "TrueAudio";
    case TB_FILE_MATROSKA: return "Matroska";
    case TB_FILE_SHORTEN: return "Shorten";
    case TB_FILE_MOD: return "Tracker-Modul";
    default: return "Unbekannt";
    }
}

/// Checks that TagLib keeps every atom of the MP4 ilst box when saving.
std::string mp4LossReason(MP4::File *file) {
    MP4::Atoms atoms(file);
    MP4::Atom *ilst = atoms.find("moov", "udta", "meta", "ilst");
    if (!ilst) return "";
    std::set<std::string> names;
    for (auto *atom : ilst->children()) {
        if (atom->length() < 8) continue;
        file->seek(atom->offset() + 8);
        ByteVector data = file->readBlock(static_cast<size_t>(atom->length() - 8));
        auto parsed = MP4::ItemFactory::instance()->parseItem(atom, data);
        const std::string atomName = toUTF8(String(atom->name(), String::Latin1));
        if (!parsed.second.isValid()) {
            // only a problem if the atom carries data
            bool payload = false;
            unsigned int pos = 0;
            while (pos + 8 <= data.size()) {
                unsigned int len = data.toUInt(pos);
                if (len < 8) break;
                if (data.mid(pos + 4, 4) == "data" && len > 16) payload = true;
                pos += len;
            }
            if (payload) return "MP4 metadata atom '" + atomName + "' cannot be preserved by TagLib";
            continue;
        }
        const std::string key = toUTF8(parsed.first);
        if (names.count(key) && atomName != "gnre" && key != "\xC2\xA9gen")
            return "duplicate MP4 metadata atom '" + key + "' would be lost";
        names.insert(key);
    }
    return "";
}

// ------------------------------------------------------------------------------------
// Audio payload checksum
// ------------------------------------------------------------------------------------

struct PayloadHasher {
    uLong crc = crc32(0L, Z_NULL, 0);
    uLong adler = adler32(0L, Z_NULL, 0);
    unsigned long long length = 0;

    void add(const ByteVector &v) {
        if (v.isEmpty()) return;
        crc = crc32(crc, reinterpret_cast<const Bytef *>(v.data()), v.size());
        adler = adler32(adler, reinterpret_cast<const Bytef *>(v.data()), v.size());
        length += v.size();
    }

    /// Adds [offset, offset + length) of the stream; false if the range is not fully readable.
    bool addRange(IOStream *s, offset_t offset, offset_t len) {
        if (offset < 0 || len < 0 || offset + len > s->length()) return false;
        s->seek(offset);
        offset_t remaining = len;
        while (remaining > 0) {
            const size_t chunk = static_cast<size_t>(std::min<offset_t>(remaining, 1 << 20));
            ByteVector block = s->readBlock(chunk);
            if (block.size() != chunk) return false;
            add(block);
            remaining -= chunk;
        }
        return true;
    }

    std::string text() const {
        char buf[64];
        std::snprintf(buf, sizeof buf, "%llu:%08lx:%08lx", length, crc & 0xffffffffUL, adler & 0xffffffffUL);
        return buf;
    }
};

ByteVector readAt(IOStream *s, offset_t offset, size_t len) {
    if (offset < 0 || offset >= s->length()) return ByteVector();
    s->seek(offset);
    return s->readBlock(len);
}

/// Size of an ID3v2 tag at `offset` (0 if there is none).
offset_t id3v2SizeAt(IOStream *s, offset_t offset) {
    ByteVector h = readAt(s, offset, 10);
    if (h.size() < 10 || !h.startsWith("ID3")) return 0;
    const unsigned char *b = reinterpret_cast<const unsigned char *>(h.data());
    offset_t size = (static_cast<offset_t>(b[6] & 0x7f) << 21) | ((b[7] & 0x7f) << 14) | ((b[8] & 0x7f) << 7) |
                    (b[9] & 0x7f);
    return 10 + size + ((b[5] & 0x10) ? 10 : 0);
}

/// End of the audio data before trailing ID3v1 and APEv2 tags.
offset_t endBeforeTrailingTags(IOStream *s) {
    offset_t end = s->length();
    if (end >= 128 && readAt(s, end - 128, 3) == "TAG") end -= 128;
    if (end >= 32) {
        ByteVector footer = readAt(s, end - 32, 32);
        if (footer.size() == 32 && footer.startsWith("APETAGEX")) {
            offset_t size = footer.toUInt(12, false);              // tag size incl. footer, excl. header
            const unsigned int flags = footer.toUInt(20, false);
            if (flags & 0x80000000U) size += 32;                     // header present
            if (size <= end) end -= size;
        }
    }
    return end;
}

/// All packets of the first logical Ogg stream except the comment header packet
/// (identification/setup headers and audio packets must stay byte-identical).
bool hashOggPackets(IOStream *s, TBFileType type, PayloadHasher &h) {
    offset_t pos = 0;
    const offset_t length = s->length();
    long long serial = -1;
    unsigned int packetIndex = 0;
    ByteVector packet;
    bool sawPage = false;
    auto finishPacket = [&]() {
        bool isComment = false;
        if (type == TB_FILE_OGG_FLAC) {
            // header packets after the first one are FLAC metadata blocks; 4 = VORBIS_COMMENT
            isComment = packetIndex > 0 && !packet.isEmpty() && (static_cast<unsigned char>(packet[0]) & 0x7F) == 4 &&
                        packet.size() >= 4;
        } else {
            isComment = packetIndex == 1;  // Vorbis, Opus, Speex: second packet = comment header
        }
        if (!isComment) {
            h.add(ByteVector::fromUInt(packet.size()));
            h.add(packet);
        }
        packet.clear();
        ++packetIndex;
    };
    while (pos + 27 <= length) {
        ByteVector header = readAt(s, pos, 27);
        if (header.size() < 27 || !header.startsWith("OggS")) return false;
        sawPage = true;
        const unsigned int pageSerial = header.toUInt(14, false);
        const unsigned int segments = static_cast<unsigned char>(header[26]);
        ByteVector table = readAt(s, pos + 27, segments);
        if (table.size() != segments) return false;
        const offset_t dataPos = pos + 27 + segments;
        offset_t pageSize = 0;
        for (unsigned int i = 0; i < segments; ++i) pageSize += static_cast<unsigned char>(table[i]);
        if (serial < 0) serial = pageSerial;
        if (pageSerial == static_cast<unsigned int>(serial)) {
            ByteVector data = readAt(s, dataPos, static_cast<size_t>(pageSize));
            if (static_cast<offset_t>(data.size()) != pageSize) return false;
            unsigned int offset = 0;
            for (unsigned int i = 0; i < segments; ++i) {
                const unsigned int lace = static_cast<unsigned char>(table[i]);
                packet.append(data.mid(offset, lace));
                offset += lace;
                if (lace < 255) finishPacket();
            }
        }
        pos = dataPos + pageSize;
    }
    if (!packet.isEmpty()) finishPacket();  // unterminated last packet
    return sawPage && packetIndex > 1;
}

/// Data range of a RIFF/FORM chunk with the given id (little/big endian sizes).
bool findChunk(IOStream *s, offset_t start, offset_t end, const ByteVector &id, bool bigEndian,
               offset_t &dataOffset, offset_t &dataSize) {
    offset_t pos = start;
    while (pos + 8 <= end) {
        ByteVector h = readAt(s, pos, 8);
        if (h.size() < 8) return false;
        const offset_t size = h.toUInt(4, bigEndian);
        if (h.mid(0, 4) == id) {
            dataOffset = pos + 8;
            dataSize = std::min<offset_t>(size, end - dataOffset);
            return true;
        }
        pos += 8 + size + (size & 1);
    }
    return false;
}

std::string payloadChecksum(TBFile *f);

} // namespace

// ====================================================================================
// The handle
// ====================================================================================

struct TBFile {
    std::string path;
    std::unique_ptr<FileStream> stream;     // destroyed after `file`
    std::unique_ptr<TagLib::File> file;
    TBFileType type = TB_FILE_UNKNOWN;
    bool sniffed = false;                    // type decided by magic bytes
    int id3v2Version = 0;                    // on disk
    int id3v2Target = 4;                     // version used when saving
    uint32_t tagTypes = 0;
    bool writable = false;
    std::string writableReason;
    std::string tagDescription;
    std::string lastError;
    std::unique_ptr<Backend> primary;
    std::vector<std::unique_ptr<Backend>> secondaries;
    bool hasID3v1 = false, hasAPE = false, hasInfo = false, hasDIIN = false;
};

namespace {

std::string payloadChecksum(TBFile *f) {
    IOStream *s = f->stream.get();
    PayloadHasher h;
    const offset_t length = s->length();
    switch (f->type) {
    case TB_FILE_MPEG: {
        auto *m = static_cast<MPEG::File *>(f->file.get());
        const offset_t first = m->firstFrameOffset();
        const offset_t last = m->lastFrameOffset();
        if (first < 0 || last < first) return "";
        MPEG::Header lastHeader(m, last, false);
        const offset_t end = last + (lastHeader.isValid() ? lastHeader.frameLength() : 0);
        if (!h.addRange(s, first, std::min(end, length) - first)) return "";
        break;
    }
    case TB_FILE_MP4: {
        MP4::Atoms atoms(f->file.get());
        // sample description and sample tables of every track (stco/co64 change when data moves)
        if (MP4::Atom *moov = atoms.find("moov")) {
            for (auto *trak : moov->findall("trak")) {
                for (const char *table : {"stsd", "stts", "stsz", "stz2", "stsc"}) {
                    if (MP4::Atom *a = trak->find("mdia", "minf", "stbl", table)) {
                        if (!h.addRange(s, a->offset(), a->length())) return "";
                    }
                }
            }
        }
        bool any = false;
        for (auto *atom : atoms.atoms()) {
            if (atom->name() != "mdat") continue;
            if (!h.addRange(s, atom->offset(), atom->length())) return "";
            any = true;
        }
        if (!any) return "";
        break;
    }
    case TB_FILE_FLAC: {
        offset_t pos = id3v2SizeAt(s, 0);
        if (readAt(s, pos, 4) != "fLaC") return "";
        pos += 4;
        while (true) {
            ByteVector header = readAt(s, pos, 4);
            if (header.size() < 4) return "";
            const bool last = (static_cast<unsigned char>(header[0]) & 0x80) != 0;
            const int blockType = static_cast<unsigned char>(header[0]) & 0x7F;
            const offset_t blockLength = static_cast<offset_t>(header.toUInt(0, true)) & 0xFFFFFF;
            // STREAMINFO, SEEKTABLE, CUESHEET are never changed by tag writing
            if ((blockType == 0 || blockType == 3 || blockType == 5) && !h.addRange(s, pos + 4, blockLength))
                return "";
            pos += 4 + blockLength;
            if (last) break;
        }
        const offset_t end = endBeforeTrailingTags(s);
        if (!h.addRange(s, pos, end - pos)) return "";
        break;
    }
    case TB_FILE_OGG_VORBIS:
    case TB_FILE_OGG_OPUS:
    case TB_FILE_OGG_SPEEX:
    case TB_FILE_OGG_FLAC:
        if (!hashOggPackets(s, f->type, h)) return "";
        break;
    case TB_FILE_WAV:
    case TB_FILE_AIFF: {
        const bool wav = f->type == TB_FILE_WAV;
        offset_t off = 0, size = 0;
        if (!findChunk(s, 12, length, wav ? "fmt " : "COMM", !wav, off, size) || !h.addRange(s, off, size))
            return "";
        if (!findChunk(s, 12, length, wav ? "data" : "SSND", !wav, off, size) || !h.addRange(s, off, size))
            return "";
        break;
    }
    case TB_FILE_DSF: {
        offset_t pos = 0;
        while (pos + 12 <= length) {
            ByteVector c = readAt(s, pos, 12);
            const offset_t size = static_cast<offset_t>(c.toLongLong(4, false));
            if (size < 12) return "";
            if (c.startsWith("fmt ") && !h.addRange(s, pos, std::min(size, length - pos))) return "";
            if (c.startsWith("data")) {
                if (!h.addRange(s, pos + 12, std::min(size, length - pos) - 12)) return "";
                break;
            }
            pos += size;
        }
        if (h.length == 0) return "";
        break;
    }
    case TB_FILE_DSDIFF: {
        offset_t pos = 16;  // "FRM8" size(8) "DSD "
        while (pos + 12 <= length) {
            ByteVector c = readAt(s, pos, 12);
            const offset_t size = static_cast<offset_t>(c.toLongLong(4, true));
            if (c.startsWith("PROP") && !h.addRange(s, pos + 12, std::min(size, length - pos - 12))) return "";
            if (c.startsWith("DSD ") || c.startsWith("DST ")) {
                if (!h.addRange(s, pos + 12, std::min(size, length - pos - 12))) return "";
                break;
            }
            pos += 12 + size + (size & 1);
        }
        if (h.length == 0) return "";
        break;
    }
    case TB_FILE_APE:
    case TB_FILE_WAVPACK:
    case TB_FILE_MPC:
    case TB_FILE_TRUEAUDIO: {
        const offset_t start = id3v2SizeAt(s, 0);
        const offset_t end = endBeforeTrailingTags(s);
        if (!h.addRange(s, start, end - start)) return "";
        break;
    }
    case TB_FILE_ASF: {
        ByteVector header = readAt(s, 0, 30);
        if (header.size() < 30) return "";
        const offset_t dataObject = static_cast<offset_t>(header.toLongLong(16, false));
        // Stream Properties Objects (codec setup) inside the header object
        static const unsigned char streamProperties[16] = {0x91, 0x07, 0xDC, 0xB7, 0xB7, 0xA9, 0xCF, 0x11,
                                                           0x8E, 0xE6, 0x00, 0xC0, 0x0C, 0x20, 0x53, 0x65};
        const ByteVector streamGuid(reinterpret_cast<const char *>(streamProperties), 16);
        const unsigned int objects = header.toUInt(24, false);
        offset_t pos = 30;
        for (unsigned int i = 0; i < objects && pos + 24 <= dataObject; ++i) {
            ByteVector object = readAt(s, pos, 24);
            const offset_t size = static_cast<offset_t>(object.toLongLong(16, false));
            if (size < 24) return "";
            if (object.mid(0, 16) == streamGuid && !h.addRange(s, pos, size)) return "";
            pos += size;
        }
        ByteVector data = readAt(s, dataObject, 24);
        if (data.size() < 24) return "";
        const offset_t size = static_cast<offset_t>(data.toLongLong(16, false));
        if (!h.addRange(s, dataObject + 24, std::min(size, length - dataObject) - 24)) return "";
        break;
    }
    default:
        return "";
    }
    return h.text();
}

TBStatus fail(TBFile *f, TBStatus status, const std::string &message) {
    if (f) f->lastError = message.empty() ? std::string(tb_status_message(status)) : message;
    return status;
}

int targetVersionFor(int onDisk) {
    if (onDisk == 3 || onDisk == 2) return 3;
    return 4;
}

void setupBackends(TBFile *f) {
    TagLib::File *file = f->file.get();
    auto addID3v1 = [f](std::function<ID3v1::Tag *(bool)> provider) {
        f->secondaries.push_back(std::make_unique<BasicBackend>(
            [provider](bool create) -> TagLib::Tag * { return provider(create); }));
    };

    switch (f->type) {
    case TB_FILE_MPEG: {
        auto *m = static_cast<MPEG::File *>(file);
        if (m->hasID3v2Tag() && m->ID3v2Tag()) {
            f->id3v2Version = static_cast<int>(m->ID3v2Tag()->header()->majorVersion());
            f->tagTypes |= TB_TAG_ID3V2;
        }
        f->id3v2Target = targetVersionFor(f->id3v2Version);
        f->hasID3v1 = m->hasID3v1Tag();
        f->hasAPE = m->hasAPETag();
        if (f->hasID3v1) f->tagTypes |= TB_TAG_ID3V1;
        if (f->hasAPE) f->tagTypes |= TB_TAG_APE;
        auto provider = [m](bool create) { return m->ID3v2Tag(create); };
        f->primary = std::make_unique<ID3v2Backend>(provider, f->id3v2Target);
        if (f->hasAPE)
            f->secondaries.push_back(std::make_unique<APEBackend>([m](bool c) { return m->APETag(c); }, false));
        if (f->hasID3v1) addID3v1([m](bool c) { return m->ID3v1Tag(c); });
        break;
    }
    case TB_FILE_MP4: {
        auto *m = static_cast<MP4::File *>(file);
        if (m->hasMP4Tag()) f->tagTypes |= TB_TAG_MP4;
        f->primary = std::make_unique<MP4Backend>(m->tag());
        break;
    }
    case TB_FILE_FLAC: {
        auto *fl = static_cast<FLAC::File *>(file);
        if (fl->hasXiphComment()) f->tagTypes |= TB_TAG_XIPH;
        if (!fl->pictureList().isEmpty()) f->tagTypes |= TB_TAG_FLAC_PICTURE;
        if (fl->hasID3v2Tag() && fl->ID3v2Tag()) {
            f->tagTypes |= TB_TAG_ID3V2;
            f->id3v2Version = static_cast<int>(fl->ID3v2Tag()->header()->majorVersion());
        }
        f->id3v2Target = 4;  // FLAC::File::save() always renders ID3v2.4
        f->hasID3v1 = fl->hasID3v1Tag();
        if (f->hasID3v1) f->tagTypes |= TB_TAG_ID3V1;
        f->primary = std::make_unique<XiphBackend>([fl](bool c) { return fl->xiphComment(c); }, fl);
        if (fl->hasID3v2Tag())
            f->secondaries.push_back(std::make_unique<ID3v2Backend>([fl](bool c) { return fl->ID3v2Tag(c); }, 4));
        if (f->hasID3v1) addID3v1([fl](bool c) { return fl->ID3v1Tag(c); });
        break;
    }
    case TB_FILE_OGG_VORBIS:
    case TB_FILE_OGG_OPUS:
    case TB_FILE_OGG_SPEEX:
    case TB_FILE_OGG_FLAC: {
        Ogg::XiphComment *x = nullptr;
        if (f->type == TB_FILE_OGG_VORBIS) x = static_cast<Ogg::Vorbis::File *>(file)->tag();
        else if (f->type == TB_FILE_OGG_OPUS) x = static_cast<Ogg::Opus::File *>(file)->tag();
        else if (f->type == TB_FILE_OGG_SPEEX) x = static_cast<Ogg::Speex::File *>(file)->tag();
        else x = static_cast<Ogg::FLAC::File *>(file)->tag();
        if (x) f->tagTypes |= TB_TAG_XIPH;
        f->primary = std::make_unique<XiphBackend>([x](bool) { return x; }, nullptr);
        break;
    }
    case TB_FILE_WAV: {
        auto *w = static_cast<RIFF::WAV::File *>(file);
        if (w->hasID3v2Tag() && w->ID3v2Tag()) {
            f->tagTypes |= TB_TAG_ID3V2;
            f->id3v2Version = static_cast<int>(w->ID3v2Tag()->header()->majorVersion());
        }
        f->id3v2Target = targetVersionFor(f->id3v2Version);
        f->hasInfo = w->hasInfoTag();
        if (f->hasInfo) f->tagTypes |= TB_TAG_RIFF_INFO;
        f->primary = std::make_unique<ID3v2Backend>([w](bool) { return w->ID3v2Tag(); }, f->id3v2Target);
        if (f->hasInfo) f->secondaries.push_back(std::make_unique<InfoBackend>(w->InfoTag()));
        break;
    }
    case TB_FILE_AIFF: {
        auto *a = static_cast<RIFF::AIFF::File *>(file);
        if (a->hasID3v2Tag() && a->tag()) {
            f->tagTypes |= TB_TAG_ID3V2;
            f->id3v2Version = static_cast<int>(a->tag()->header()->majorVersion());
        }
        f->id3v2Target = targetVersionFor(f->id3v2Version);
        f->primary = std::make_unique<ID3v2Backend>([a](bool) { return a->tag(); }, f->id3v2Target);
        break;
    }
    case TB_FILE_DSF: {
        auto *d = static_cast<DSF::File *>(file);
        if (d->tag() && d->tag()->header()->tagSize() > 0) {
            f->tagTypes |= TB_TAG_ID3V2;
            f->id3v2Version = static_cast<int>(d->tag()->header()->majorVersion());
        }
        f->id3v2Target = targetVersionFor(f->id3v2Version);
        f->primary = std::make_unique<ID3v2Backend>([d](bool) { return d->tag(); }, f->id3v2Target);
        break;
    }
    case TB_FILE_DSDIFF: {
        auto *d = static_cast<DSDIFF::File *>(file);
        if (d->hasID3v2Tag() && d->ID3v2Tag()) {
            f->tagTypes |= TB_TAG_ID3V2;
            f->id3v2Version = static_cast<int>(d->ID3v2Tag()->header()->majorVersion());
        }
        f->id3v2Target = targetVersionFor(f->id3v2Version);
        f->hasDIIN = d->hasDIINTag();
        if (f->hasDIIN) f->tagTypes |= TB_TAG_DIIN;
        f->primary = std::make_unique<ID3v2Backend>([d](bool c) { return d->ID3v2Tag(c); }, f->id3v2Target);
        if (f->hasDIIN) f->secondaries.push_back(std::make_unique<DIINBackend>(d->DIINTag()));
        break;
    }
    case TB_FILE_TRUEAUDIO: {
        auto *t = static_cast<TrueAudio::File *>(file);
        if (t->hasID3v2Tag() && t->ID3v2Tag()) {
            f->tagTypes |= TB_TAG_ID3V2;
            f->id3v2Version = static_cast<int>(t->ID3v2Tag()->header()->majorVersion());
        }
        f->id3v2Target = 4;  // TrueAudio::File::save() always renders ID3v2.4
        f->hasID3v1 = t->hasID3v1Tag();
        if (f->hasID3v1) f->tagTypes |= TB_TAG_ID3V1;
        f->primary = std::make_unique<ID3v2Backend>([t](bool c) { return t->ID3v2Tag(c); }, 4);
        if (f->hasID3v1) addID3v1([t](bool c) { return t->ID3v1Tag(c); });
        break;
    }
    case TB_FILE_APE:
    case TB_FILE_WAVPACK:
    case TB_FILE_MPC: {
        std::function<APE::Tag *(bool)> apeProvider;
        std::function<ID3v1::Tag *(bool)> v1Provider;
        bool hasAPE = false;
        if (f->type == TB_FILE_APE) {
            auto *a = static_cast<APE::File *>(file);
            apeProvider = [a](bool c) { return a->APETag(c); };
            v1Provider = [a](bool c) { return a->ID3v1Tag(c); };
            hasAPE = a->hasAPETag();
            f->hasID3v1 = a->hasID3v1Tag();
        } else if (f->type == TB_FILE_WAVPACK) {
            auto *a = static_cast<WavPack::File *>(file);
            apeProvider = [a](bool c) { return a->APETag(c); };
            v1Provider = [a](bool c) { return a->ID3v1Tag(c); };
            hasAPE = a->hasAPETag();
            f->hasID3v1 = a->hasID3v1Tag();
        } else {
            auto *a = static_cast<MPC::File *>(file);
            apeProvider = [a](bool c) { return a->APETag(c); };
            v1Provider = [a](bool c) { return a->ID3v1Tag(c); };
            hasAPE = a->hasAPETag();
            f->hasID3v1 = a->hasID3v1Tag();
        }
        if (hasAPE) f->tagTypes |= TB_TAG_APE;
        if (f->hasID3v1) f->tagTypes |= TB_TAG_ID3V1;
        f->primary = std::make_unique<APEBackend>(apeProvider, true);
        if (f->hasID3v1) addID3v1(v1Provider);
        break;
    }
    case TB_FILE_ASF: {
        auto *a = static_cast<ASF::File *>(file);
        f->tagTypes |= TB_TAG_ASF;
        f->primary = std::make_unique<ASFBackend>(a->tag());
        break;
    }
    case TB_FILE_MATROSKA: {
        f->tagTypes |= TB_TAG_MATROSKA;
        f->primary = std::make_unique<PropertyBackend>(file, nullptr, propertyConfig());
        break;
    }
    default: {
        f->tagTypes |= TB_TAG_OTHER;
        f->primary = std::make_unique<PropertyBackend>(file, nullptr, propertyConfig());
        break;
    }
    }

    // ----- description
    std::vector<std::string> parts;
    if (f->tagTypes & TB_TAG_ID3V2) parts.push_back("ID3v2." + std::to_string(f->id3v2Version));
    if (f->tagTypes & TB_TAG_ID3V1) parts.push_back("ID3v1");
    if (f->tagTypes & TB_TAG_APE) parts.push_back("APEv2");
    if (f->tagTypes & TB_TAG_XIPH) parts.push_back("Vorbis Comment");
    if (f->tagTypes & TB_TAG_FLAC_PICTURE) parts.push_back("FLAC Picture");
    if (f->tagTypes & TB_TAG_MP4) parts.push_back("MP4");
    if (f->tagTypes & TB_TAG_ASF) parts.push_back("ASF");
    if (f->tagTypes & TB_TAG_RIFF_INFO) parts.push_back("RIFF INFO");
    if (f->tagTypes & TB_TAG_DIIN) parts.push_back("DIIN");
    if (f->tagTypes & TB_TAG_MATROSKA) parts.push_back("Matroska");
    for (size_t i = 0; i < parts.size(); ++i) {
        if (i) f->tagDescription += ", ";
        f->tagDescription += parts[i];
    }
}

void computeWritable(TBFile *f) {
    f->writable = false;
    switch (f->type) {
    case TB_FILE_MATROSKA:
    case TB_FILE_SHORTEN:
    case TB_FILE_MOD:
    case TB_FILE_UNKNOWN:
        f->writableReason = std::string("writing is not supported for ") + formatName(f->type);
        return;
    default: break;
    }
    if (!f->sniffed && f->type != TB_FILE_MPEG) {
        f->writableReason = "file type could not be verified from the file header";
        return;
    }
    if (f->type == TB_FILE_MPEG) {
        auto *m = static_cast<MPEG::File *>(f->file.get());
        offset_t tagEnd = 0;
        if (m->hasID3v2Tag() && m->ID3v2Tag()) tagEnd = m->ID3v2Tag()->header()->completeTagSize();
        offset_t first = m->firstFrameOffset();
        if (first < 0 || first > tagEnd + 65536) {
            f->writableReason = "MPEG audio data does not start near the beginning of the file";
            return;
        }
    }
    if (f->type == TB_FILE_MP4) {
        std::string reason = mp4LossReason(static_cast<MP4::File *>(f->file.get()));
        if (!reason.empty()) {
            f->writableReason = reason;
            return;
        }
    }
    // ID3v2 frames that TagLib would drop
    std::vector<Backend *> id3Backends;
    id3Backends.push_back(f->primary.get());
    for (auto &s : f->secondaries) id3Backends.push_back(s.get());
    for (Backend *b : id3Backends) {
        if (auto *id3 = dynamic_cast<ID3v2Backend *>(b)) {
            std::string reason = id3->lossReason();
            if (!reason.empty()) {
                f->writableReason = reason;
                return;
            }
        }
    }
    f->writable = true;
    f->writableReason.clear();
}

void fillCodec(TBFile *f, TBAudioProperties *out) {
    std::string codec;
    AudioProperties *ap = f->file->audioProperties();
    switch (f->type) {
    case TB_FILE_MPEG: {
        auto *p = dynamic_cast<MPEG::Properties *>(ap);
        if (p && p->isADTS()) codec = "AAC";
        else if (p && p->layer() == 1) codec = "MP1";
        else if (p && p->layer() == 2) codec = "MP2";
        else codec = "MP3";
        break;
    }
    case TB_FILE_MP4: {
        auto *p = dynamic_cast<MP4::Properties *>(ap);
        switch (p ? p->codec() : MP4::Properties::Unknown) {
        case MP4::Properties::AAC: codec = "AAC"; break;
        case MP4::Properties::ALAC: codec = "ALAC"; break;
        case MP4::Properties::AC3: codec = "AC-3"; break;
        case MP4::Properties::EAC3: codec = "E-AC-3"; break;
        case MP4::Properties::FLAC: codec = "FLAC"; break;
        case MP4::Properties::DTS: codec = "DTS"; break;
        case MP4::Properties::Opus: codec = "Opus"; break;
        default: codec = "MPEG-4"; break;
        }
        if (p && (p->codec() == MP4::Properties::ALAC || p->codec() == MP4::Properties::FLAC))
            out->bitsPerSample = p->bitsPerSample();  // lossy codecs have no bit depth
        break;
    }
    case TB_FILE_FLAC:
        codec = "FLAC";
        if (auto *p = dynamic_cast<FLAC::Properties *>(ap)) out->bitsPerSample = p->bitsPerSample();
        break;
    case TB_FILE_OGG_FLAC:
        codec = "FLAC";
        if (auto *p = dynamic_cast<FLAC::Properties *>(ap)) out->bitsPerSample = p->bitsPerSample();
        break;
    case TB_FILE_OGG_VORBIS: codec = "Vorbis"; break;
    case TB_FILE_OGG_OPUS: codec = "Opus"; break;
    case TB_FILE_OGG_SPEEX: codec = "Speex"; break;
    case TB_FILE_WAV: {
        auto *p = dynamic_cast<RIFF::WAV::Properties *>(ap);
        int fmt = p ? p->format() : 1;
        if (fmt == 1 || fmt == 0xFFFE) codec = "PCM";
        else if (fmt == 3) codec = "PCM Float";
        else if (fmt == 6) codec = "A-law";
        else if (fmt == 7) codec = "mu-law";
        else if (fmt == 0x55) codec = "MP3";
        else if (fmt == 2 || fmt == 0x11) codec = "ADPCM";
        else codec = "WAV";
        if (p) out->bitsPerSample = p->bitsPerSample();
        break;
    }
    case TB_FILE_AIFF: {
        auto *p = dynamic_cast<RIFF::AIFF::Properties *>(ap);
        codec = "PCM";
        if (p && p->isAiffC()) {
            ByteVector c = p->compressionType();
            if (c == "NONE" || c == "sowt" || c == "twos" || c == "raw " || c == "in24" || c == "in32") codec = "PCM";
            else if (c == "fl32" || c == "FL32" || c == "fl64" || c == "FL64") codec = "PCM Float";
            else if (c == "alaw" || c == "ALAW") codec = "A-law";
            else if (c == "ulaw" || c == "ULAW") codec = "mu-law";
            else codec = toUTF8(p->compressionName());
            if (codec.empty()) codec = "AIFF-C";
        }
        if (p) out->bitsPerSample = p->bitsPerSample();
        break;
    }
    case TB_FILE_APE:
        codec = "Monkey's Audio";
        if (auto *p = dynamic_cast<APE::Properties *>(ap)) out->bitsPerSample = p->bitsPerSample();
        break;
    case TB_FILE_WAVPACK:
        codec = "WavPack";
        if (auto *p = dynamic_cast<WavPack::Properties *>(ap)) out->bitsPerSample = p->bitsPerSample();
        break;
    case TB_FILE_MPC: codec = "Musepack"; break;
    case TB_FILE_TRUEAUDIO:
        codec = "TTA";
        if (auto *p = dynamic_cast<TrueAudio::Properties *>(ap)) out->bitsPerSample = p->bitsPerSample();
        break;
    case TB_FILE_ASF: {
        auto *p = dynamic_cast<ASF::Properties *>(ap);
        codec = "WMA";
        if (p && p->codec() == ASF::Properties::WMA9Pro) codec = "WMA Pro";
        if (p && p->codec() == ASF::Properties::WMA9Lossless) {
            codec = "WMA Lossless";
            out->bitsPerSample = p->bitsPerSample();
        }
        break;
    }
    case TB_FILE_DSF:
        codec = "DSD";
        if (auto *p = dynamic_cast<DSF::Properties *>(ap)) out->bitsPerSample = p->bitsPerSample();
        break;
    case TB_FILE_DSDIFF:
        codec = "DSD";
        if (auto *p = dynamic_cast<DSDIFF::Properties *>(ap)) out->bitsPerSample = p->bitsPerSample();
        break;
    case TB_FILE_MATROSKA: {
        auto *p = dynamic_cast<Matroska::Properties *>(ap);
        codec = p ? toUTF8(p->codecName()) : "Matroska";
        if (codec.rfind("A_", 0) == 0) codec = codec.substr(2);
        if (p) out->bitsPerSample = p->bitsPerSample();
        break;
    }
    case TB_FILE_SHORTEN: codec = "Shorten"; break;
    case TB_FILE_MOD: codec = "Tracker"; break;
    default: codec = ""; break;
    }
    std::snprintf(out->codec, sizeof out->codec, "%s", codec.c_str());
}

std::vector<Pic> picsFromC(const TBPicture *pictures, size_t count) {
    std::vector<Pic> out;
    for (size_t i = 0; i < count; ++i) {
        const TBPicture &c = pictures[i];
        Pic p;
        p.type = clampPictureType(c.type);
        p.data = ByteVector(reinterpret_cast<const char *>(c.data), static_cast<unsigned int>(c.size));
        p.mimeType = normalizedMime(fromUTF8(c.mimeType), p.data);
        p.description = fromUTF8(c.description);
        p.width = c.width;
        p.height = c.height;
        p.colorDepth = c.colorDepth;
        p.numColors = c.numColors;
        out.push_back(p);
    }
    return out;
}

char *dupString(const std::string &s) {
    char *p = static_cast<char *>(std::malloc(s.size() + 1));
    if (!p) throw std::bad_alloc();
    std::memcpy(p, s.data(), s.size());
    p[s.size()] = '\0';
    return p;
}

TBStringList *makeStringList(const StringList &values) {
    auto *list = static_cast<TBStringList *>(std::calloc(1, sizeof(TBStringList)));
    if (!list) throw std::bad_alloc();
    if (values.isEmpty()) return list;
    list->items = static_cast<char **>(std::calloc(values.size(), sizeof(char *)));
    if (!list->items) {
        std::free(list);
        throw std::bad_alloc();
    }
    for (const auto &v : values) {
        try {
            list->items[list->count] = dupString(toUTF8(v));
        } catch (...) {
            tb_string_list_free(list);
            throw;
        }
        list->count++;
    }
    return list;
}

template <typename Fn>
TBStatus guarded(TBFile *f, Fn &&fn) {
    try {
        if (f) f->lastError.clear();
        return fn();
    } catch (const std::bad_alloc &) {
        return fail(f, TB_ERROR_OUT_OF_MEMORY, "out of memory");
    } catch (const std::exception &e) {
        return fail(f, TB_ERROR_INTERNAL, std::string("internal error: ") + e.what());
    } catch (...) {
        return fail(f, TB_ERROR_INTERNAL, "internal error");
    }
}

} // namespace

// ====================================================================================
// C API
// ====================================================================================

extern "C" {

const char *tb_taglib_version(void) {
    return "2.3.2";
}

const char *tb_status_message(TBStatus status) {
    switch (status) {
    case TB_OK: return "OK";
    case TB_ERROR_INVALID_ARGUMENT: return "invalid argument";
    case TB_ERROR_FILE_NOT_FOUND: return "file not found";
    case TB_ERROR_OPEN_FAILED: return "file could not be opened";
    case TB_ERROR_UNSUPPORTED_FORMAT: return "unsupported file format";
    case TB_ERROR_INVALID_FILE: return "file is damaged or not a valid audio file";
    case TB_ERROR_READ_ONLY: return "file cannot be written";
    case TB_ERROR_UNSUPPORTED_FIELD: return "field is not supported by this tag format";
    case TB_ERROR_SAVE_FAILED: return "saving the tags failed";
    case TB_ERROR_OUT_OF_MEMORY: return "out of memory";
    case TB_ERROR_INTERNAL: return "internal error";
    }
    return "unknown error";
}

TBStatus tb_open(const char *path, uint32_t flags, TBFile **outFile) {
    if (!outFile) return TB_ERROR_INVALID_ARGUMENT;
    *outFile = nullptr;
    if (!path || !*path) return TB_ERROR_INVALID_ARGUMENT;
    try {
        struct stat st;
        if (::stat(path, &st) != 0) {
            if (errno == ENOENT || errno == ENOTDIR) return TB_ERROR_FILE_NOT_FOUND;
            return TB_ERROR_OPEN_FAILED;
        }
        if (!S_ISREG(st.st_mode)) return TB_ERROR_OPEN_FAILED;

        auto f = std::make_unique<TBFile>();
        f->path = path;
        const bool readOnly = (flags & TB_OPEN_READ_ONLY) != 0;
        f->stream = std::make_unique<FileStream>(path, readOnly);
        if (!f->stream->isOpen()) return TB_ERROR_OPEN_FAILED;

        const bool readProps = (flags & TB_OPEN_NO_AUDIO_PROPERTIES) == 0;
        const auto style = (flags & TB_OPEN_ACCURATE_AUDIO_PROPERTIES) ? AudioProperties::Accurate
                                                                        : AudioProperties::Average;
        TBFileType type = sniffType(f->stream.get());
        f->sniffed = type != TB_FILE_UNKNOWN;
        if (type == TB_FILE_UNKNOWN) type = typeFromExtension(f->path);
        std::unique_ptr<TagLib::File> file;
        if (type != TB_FILE_UNKNOWN) {
            file = createFile(type, f->stream.get(), f->path, readProps, style);
            if (file && !file->isValid()) {
                if (f->sniffed) return TB_ERROR_INVALID_FILE;  // magic matched but TagLib refuses it
                file.reset();
            }
        }
        if (!file) {
            f->stream->seek(0);
            type = detectByContent(f->stream.get());
            if (type == TB_FILE_UNKNOWN) return TB_ERROR_UNSUPPORTED_FORMAT;
            file = createFile(type, f->stream.get(), f->path, readProps, style);
            if (!file || !file->isValid()) return TB_ERROR_INVALID_FILE;
        }
        if (type == TB_FILE_MPEG && static_cast<MPEG::File *>(file.get())->firstFrameOffset() < 0)
            return TB_ERROR_INVALID_FILE;  // no MPEG frame at all
        f->type = type;
        f->file = std::move(file);
        setupBackends(f.get());
        computeWritable(f.get());
        *outFile = f.release();
        return TB_OK;
    } catch (const std::bad_alloc &) {
        return TB_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return TB_ERROR_INTERNAL;
    }
}

void tb_close(TBFile *file) {
    if (!file) return;
    try {
        file->secondaries.clear();
        file->primary.reset();
        file->file.reset();
        file->stream.reset();
        delete file;
    } catch (...) {
    }
}

const char *tb_last_error(const TBFile *file) {
    return file ? file->lastError.c_str() : "";
}

TBFileType tb_file_type(const TBFile *file) {
    return file ? file->type : TB_FILE_UNKNOWN;
}

const char *tb_file_format_name(const TBFile *file) {
    return formatName(file ? file->type : TB_FILE_UNKNOWN);
}

uint32_t tb_tag_types(const TBFile *file) {
    return file ? file->tagTypes : 0;
}

int32_t tb_id3v2_version(const TBFile *file) {
    return file ? file->id3v2Version : 0;
}

const char *tb_tag_format_description(const TBFile *file) {
    return file ? file->tagDescription.c_str() : "";
}

int32_t tb_is_writable(const TBFile *file) {
    return (file && file->writable) ? 1 : 0;
}

const char *tb_writable_reason(const TBFile *file) {
    return file ? file->writableReason.c_str() : "";
}

int32_t tb_handle_is_read_only(const TBFile *file) {
    return (!file || !file->stream || file->stream->readOnly()) ? 1 : 0;
}

int32_t tb_supports_pictures(const TBFile *file) {
    try {
        return (file && file->primary && file->primary->supportsPictures()) ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

int32_t tb_field_supported(const TBFile *file, TBField field) {
    try {
        if (!file || !file->primary) return 0;
        if (!isTextField(field) && !isIntField(field)) return 0;
        return file->primary->supports(field) ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

TBStatus tb_audio_properties(const TBFile *cfile, TBAudioProperties *out) {
    TBFile *file = const_cast<TBFile *>(cfile);
    if (!file || !out) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        std::memset(out, 0, sizeof *out);
        AudioProperties *ap = file->file->audioProperties();
        if (!ap) return fail(file, TB_ERROR_INVALID_ARGUMENT, "audio properties were not read");
        out->durationMs = ap->lengthInMilliseconds();
        out->bitrateKbps = ap->bitrate();
        out->sampleRate = ap->sampleRate();
        out->channels = ap->channels();
        fillCodec(file, out);
        return TB_OK;
    });
}

TBStatus tb_audio_payload_checksum(TBFile *file, char *out, size_t outSize) {
    if (!file || !out || outSize == 0) return TB_ERROR_INVALID_ARGUMENT;
    out[0] = '\0';
    return guarded(file, [&]() -> TBStatus {
        const std::string sum = payloadChecksum(file);
        if (sum.empty())
            return fail(file, TB_ERROR_UNSUPPORTED_FORMAT, "audio payload layout not known for this file");
        if (sum.size() + 1 > outSize) return fail(file, TB_ERROR_INVALID_ARGUMENT, "buffer too small");
        std::memcpy(out, sum.c_str(), sum.size() + 1);
        return TB_OK;
    });
}

TBStatus tb_get_strings(TBFile *file, TBField field, TBStringList **out) {
    if (!file || !out) return TB_ERROR_INVALID_ARGUMENT;
    *out = nullptr;
    return guarded(file, [&]() -> TBStatus {
        if (!isTextField(field)) return fail(file, TB_ERROR_INVALID_ARGUMENT, "not a text field");
        StringList values;
        if (file->primary->supports(field)) values = cleaned(file->primary->getStrings(field));
        if (values.isEmpty()) {
            for (auto &s : file->secondaries) {
                if (!s->supports(field)) continue;
                values = cleaned(s->getStrings(field));
                if (!values.isEmpty()) break;
            }
        }
        *out = makeStringList(values);
        return TB_OK;
    });
}

TBStatus tb_set_strings(TBFile *file, TBField field, const char *const *values, size_t count) {
    if (!file || (count > 0 && !values)) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        if (!isTextField(field) || field == TB_FIELD_DATE)
            return fail(file, TB_ERROR_INVALID_ARGUMENT, "not a writable text field");
        if (!file->primary->supports(field))
            return fail(file, TB_ERROR_UNSUPPORTED_FIELD, "the tag format cannot store this field");
        StringList list = fromCArray(values, count);
        file->primary->setStrings(field, list);
        for (auto &s : file->secondaries) {
            if (s->supports(field)) s->setStrings(field, list);
        }
        return TB_OK;
    });
}

TBStatus tb_get_int(TBFile *file, TBField field, int64_t *value, int32_t *hasValue) {
    if (!file || !value || !hasValue) return TB_ERROR_INVALID_ARGUMENT;
    *value = 0;
    *hasValue = 0;
    return guarded(file, [&]() -> TBStatus {
        if (!isIntField(field)) return fail(file, TB_ERROR_INVALID_ARGUMENT, "not a numeric field");
        std::optional<long long> v;
        if (file->primary->supports(field)) v = file->primary->getInt(field);
        if (!v) {
            for (auto &s : file->secondaries) {
                if (!s->supports(field)) continue;
                v = s->getInt(field);
                if (v) break;
            }
        }
        if (v) {
            *value = *v;
            *hasValue = 1;
        }
        return TB_OK;
    });
}

TBStatus tb_set_int(TBFile *file, TBField field, int64_t value, int32_t hasValue) {
    if (!file) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        if (!isIntField(field)) return fail(file, TB_ERROR_INVALID_ARGUMENT, "not a numeric field");
        if (!file->primary->supports(field))
            return fail(file, TB_ERROR_UNSUPPORTED_FIELD, "the tag format cannot store this field");
        if (hasValue && (value < 0 || value > 1000000000LL))
            return fail(file, TB_ERROR_INVALID_ARGUMENT, "value out of range");
        if (hasValue && field == TB_FIELD_RATING && value > 100)
            return fail(file, TB_ERROR_INVALID_ARGUMENT, "rating must be 0...100");
        std::optional<long long> v;
        if (hasValue) v = value;
        file->primary->setInt(field, v);
        for (auto &s : file->secondaries) {
            if (s->supports(field)) s->setInt(field, v);
        }
        return TB_OK;
    });
}

TBStatus tb_get_pictures(TBFile *file, TBPictureList **out) {
    if (!file || !out) return TB_ERROR_INVALID_ARGUMENT;
    *out = nullptr;
    return guarded(file, [&]() -> TBStatus {
        std::vector<Pic> pics;
        if (file->primary->supportsPictures()) pics = file->primary->getPictures();
        auto *list = static_cast<TBPictureList *>(std::calloc(1, sizeof(TBPictureList)));
        if (!list) throw std::bad_alloc();
        if (!pics.empty()) {
            list->items = static_cast<TBPicture *>(std::calloc(pics.size(), sizeof(TBPicture)));
            if (!list->items) {
                std::free(list);
                throw std::bad_alloc();
            }
        }
        try {
            for (const auto &p : pics) {
                TBPicture &c = list->items[list->count];
                c.type = p.type;
                c.mimeType = dupString(toUTF8(p.mimeType));
                c.description = dupString(toUTF8(p.description));
                c.size = p.data.size();
                uint8_t *bytes = static_cast<uint8_t *>(std::malloc(c.size > 0 ? c.size : 1));
                if (!bytes) throw std::bad_alloc();
                if (c.size) std::memcpy(bytes, p.data.data(), c.size);
                c.data = bytes;
                c.width = p.width;
                c.height = p.height;
                c.colorDepth = p.colorDepth;
                c.numColors = p.numColors;
                list->count++;
            }
        } catch (...) {
            // free the partially filled entry too
            if (list->items && list->count < pics.size()) {
                TBPicture &c = list->items[list->count];
                std::free(const_cast<char *>(c.mimeType));
                std::free(const_cast<char *>(c.description));
                std::free(const_cast<uint8_t *>(c.data));
            }
            tb_picture_list_free(list);
            throw;
        }
        *out = list;
        return TB_OK;
    });
}

TBStatus tb_set_pictures(TBFile *file, const TBPicture *pictures, size_t count) {
    if (!file || (count > 0 && !pictures)) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        if (!file->primary->supportsPictures())
            return fail(file, TB_ERROR_UNSUPPORTED_FIELD, "the tag format cannot store pictures");
        for (size_t i = 0; i < count; ++i) {
            if (!pictures[i].data || pictures[i].size == 0)
                return fail(file, TB_ERROR_INVALID_ARGUMENT, "picture without data");
            if (pictures[i].size > 0x7FFFFFFF) return fail(file, TB_ERROR_INVALID_ARGUMENT, "picture too large");
        }
        file->primary->setPictures(picsFromC(pictures, count));
        return TB_OK;
    });
}

TBStatus tb_add_picture(TBFile *file, const TBPicture *picture) {
    if (!file || !picture || !picture->data || picture->size == 0) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        if (!file->primary->supportsPictures())
            return fail(file, TB_ERROR_UNSUPPORTED_FIELD, "the tag format cannot store pictures");
        std::vector<Pic> pics = file->primary->getPictures();
        std::vector<Pic> added = picsFromC(picture, 1);
        pics.push_back(added.front());
        file->primary->setPictures(pics);
        return TB_OK;
    });
}

TBStatus tb_remove_picture(TBFile *file, size_t index) {
    if (!file) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        if (!file->primary->supportsPictures())
            return fail(file, TB_ERROR_UNSUPPORTED_FIELD, "the tag format cannot store pictures");
        std::vector<Pic> pics = file->primary->getPictures();
        if (index >= pics.size()) return fail(file, TB_ERROR_INVALID_ARGUMENT, "picture index out of range");
        pics.erase(pics.begin() + static_cast<long>(index));
        file->primary->setPictures(pics);
        return TB_OK;
    });
}

TBStatus tb_replace_picture(TBFile *file, size_t index, const TBPicture *picture) {
    if (!file || !picture || !picture->data || picture->size == 0) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        if (!file->primary->supportsPictures())
            return fail(file, TB_ERROR_UNSUPPORTED_FIELD, "the tag format cannot store pictures");
        std::vector<Pic> pics = file->primary->getPictures();
        if (index >= pics.size()) return fail(file, TB_ERROR_INVALID_ARGUMENT, "picture index out of range");
        pics[index] = picsFromC(picture, 1).front();
        file->primary->setPictures(pics);
        return TB_OK;
    });
}

TBStatus tb_get_property_keys(TBFile *file, TBStringList **out) {
    if (!file || !out) return TB_ERROR_INVALID_ARGUMENT;
    *out = nullptr;
    return guarded(file, [&]() -> TBStatus {
        StringList keys;
        for (const auto &kv : file->file->properties()) keys.append(kv.first);
        *out = makeStringList(keys);
        return TB_OK;
    });
}

TBStatus tb_get_property(TBFile *file, const char *key, TBStringList **out) {
    if (!file || !key || !out) return TB_ERROR_INVALID_ARGUMENT;
    *out = nullptr;
    return guarded(file, [&]() -> TBStatus {
        PropertyMap m = file->file->properties();
        auto it = m.find(fromUTF8(key).upper());
        *out = makeStringList(it == m.end() ? StringList() : it->second);
        return TB_OK;
    });
}

TBStatus tb_set_property(TBFile *file, const char *key, const char *const *values, size_t count) {
    if (!file || !key || (count > 0 && !values)) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        PropertyMap m = file->file->properties();
        const String k = fromUTF8(key).upper();
        StringList list = fromCArray(values, count);
        if (list.isEmpty()) m.erase(k);
        else m.replace(k, list);
        PropertyMap rejected = file->file->setProperties(m);
        if (!list.isEmpty() && rejected.contains(k))
            return fail(file, TB_ERROR_UNSUPPORTED_FIELD, "the tag format cannot store this property");
        return TB_OK;
    });
}

TBStatus tb_get_unsupported_properties(TBFile *file, TBStringList **out) {
    if (!file || !out) return TB_ERROR_INVALID_ARGUMENT;
    *out = nullptr;
    return guarded(file, [&]() -> TBStatus {
        *out = makeStringList(file->file->properties().unsupportedData());
        return TB_OK;
    });
}

TBStatus tb_save(TBFile *file) {
    if (!file) return TB_ERROR_INVALID_ARGUMENT;
    return guarded(file, [&]() -> TBStatus {
        if (!file->writable)
            return fail(file, TB_ERROR_READ_ONLY, "file cannot be written: " + file->writableReason);
        if (file->stream->readOnly())
            return fail(file, TB_ERROR_READ_ONLY, "file is opened read-only (no write permission?)");
        const ID3v2::Version version = file->id3v2Target == 3 ? ID3v2::v3 : ID3v2::v4;
        TagLib::File *tf = file->file.get();
        bool ok = false;
        switch (file->type) {
        case TB_FILE_MPEG: {
            int tags = MPEG::File::ID3v2;
            if (file->hasID3v1) tags |= MPEG::File::ID3v1;
            if (file->hasAPE) tags |= MPEG::File::APE;
            ok = static_cast<MPEG::File *>(tf)->save(tags, TagLib::File::StripNone, version,
                                                     TagLib::File::DoNotDuplicate);
            break;
        }
        case TB_FILE_WAV: {
            int tags = RIFF::WAV::File::ID3v2;
            if (file->hasInfo) tags |= RIFF::WAV::File::Info;
            ok = static_cast<RIFF::WAV::File *>(tf)->save(static_cast<RIFF::WAV::File::TagTypes>(tags),
                                                          TagLib::File::StripNone, version);
            break;
        }
        case TB_FILE_AIFF: ok = static_cast<RIFF::AIFF::File *>(tf)->save(version); break;
        case TB_FILE_DSF: ok = static_cast<DSF::File *>(tf)->save(version); break;
        case TB_FILE_DSDIFF: {
            int tags = DSDIFF::File::ID3v2;
            if (file->hasDIIN) tags |= DSDIFF::File::DIIN;
            ok = static_cast<DSDIFF::File *>(tf)->save(tags, TagLib::File::StripNone, version);
            break;
        }
        default: ok = tf->save(); break;
        }
        if (!ok) return fail(file, TB_ERROR_SAVE_FAILED, "TagLib could not save the file");
        return TB_OK;
    });
}

void tb_string_list_free(TBStringList *list) {
    if (!list) return;
    for (size_t i = 0; i < list->count; ++i) std::free(list->items[i]);
    std::free(list->items);
    std::free(list);
}

void tb_picture_list_free(TBPictureList *list) {
    if (!list) return;
    for (size_t i = 0; i < list->count; ++i) {
        std::free(const_cast<char *>(list->items[i].mimeType));
        std::free(const_cast<char *>(list->items[i].description));
        std::free(const_cast<uint8_t *>(list->items[i].data));
    }
    std::free(list->items);
    std::free(list);
}

} // extern "C"
