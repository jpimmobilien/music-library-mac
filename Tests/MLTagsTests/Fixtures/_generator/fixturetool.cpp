// fixturetool – adds data to the ffmpeg-generated test fixtures that ffmpeg cannot write:
// embedded covers for Ogg/WAV/WMA/WavPack/TTA/DSD, unknown ID3v2 frames (PRIV, XTST),
// legacy/extra frames, MP4 atoms TagLib does not map, APE tags in MP3.
// It uses TagLib's own C++ API (not the TagBridge C API under test).
//
// Usage: fixturetool <kind> <file> <cover.png> <cover.jpg> <marker>

#include <cstdio>
#include <fstream>
#include <iterator>
#include <memory>
#include <string>
#include <vector>

#include "tbytevector.h"
#include "tstring.h"
#include "mpegfile.h"
#include "id3v1tag.h"
#include "id3v2tag.h"
#include "id3v2frame.h"
#include "attachedpictureframe.h"
#include "commentsframe.h"
#include "popularimeterframe.h"
#include "privateframe.h"
#include "textidentificationframe.h"
#include "unknownframe.h"
#include "unsynchronizedlyricsframe.h"
#include "apetag.h"
#include "apeitem.h"
#include "mp4file.h"
#include "mp4tag.h"
#include "xiphcomment.h"
#include "flacpicture.h"
#include "vorbisfile.h"
#include "opusfile.h"
#include "speexfile.h"
#include "oggflacfile.h"
#include "wavfile.h"
#include "aifffile.h"
#include "asffile.h"
#include "asftag.h"
#include "asfpicture.h"
#include "wavpackfile.h"
#include "trueaudiofile.h"
#include "dsffile.h"
#include "dsdifffile.h"

using namespace TagLib;

static ByteVector readFile(const char *path) {
    std::ifstream in(path, std::ios::binary);
    std::vector<char> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    return ByteVector(bytes.data(), static_cast<unsigned int>(bytes.size()));
}

static void addUnknownFrames(ID3v2::Tag *tag, const std::string &marker) {
    auto *priv = new ID3v2::PrivateFrame();
    priv->setOwner("org.example.mltest");
    priv->setData(ByteVector((marker + "-PRIV").c_str()));
    tag->addFrame(priv);
    // An unknown frame "XTST" (size < 128, so the size field is identical in v2.3 and v2.4).
    std::string payload = marker + "-XTST";
    ByteVector raw("XTST");
    raw.append(ByteVector::fromUInt(static_cast<unsigned int>(payload.size())));
    raw.append(ByteVector(2, '\0'));
    raw.append(ByteVector(payload.c_str()));
    tag->addFrame(new ID3v2::UnknownFrame(raw));
    auto *txxx = new ID3v2::UserTextIdentificationFrame(String::UTF8);
    txxx->setDescription("MLTEST_CUSTOM");
    txxx->setText(String(marker + "-CUSTOM"));
    tag->addFrame(txxx);
}

static void addID3Extras(ID3v2::Tag *tag) {
    // iTunes normalisation comment (must be preserved, must not be read as the comment)
    auto *norm = new ID3v2::CommentsFrame(String::Latin1);
    norm->setLanguage("eng");
    norm->setDescription("iTunNORM");
    norm->setText(" 00000123 00000456 00000789");
    tag->addFrame(norm);
    // play counter in a foreign POPM frame (must be kept when the rating changes)
    auto *popm = new ID3v2::PopularimeterFrame();
    popm->setEmail("player@example.org");
    popm->setRating(196);
    popm->setCounter(7);
    tag->addFrame(popm);
    // lyrics in German (language must be kept)
    auto *uslt = new ID3v2::UnsynchronizedLyricsFrame(String::UTF8);
    uslt->setLanguage("deu");
    uslt->setText("Erste Zeile\nZweite Zeile");
    tag->addFrame(uslt);
}

static ID3v2::AttachedPictureFrame *picture(const ByteVector &data, const char *mime, int type, const char *desc) {
    auto *f = new ID3v2::AttachedPictureFrame();
    f->setMimeType(mime);
    f->setType(static_cast<ID3v2::AttachedPictureFrame::Type>(type));
    f->setDescription(desc);
    f->setPicture(data);
    return f;
}

static void setBasicID3(ID3v2::Tag *tag) {
    auto set = [tag](const char *id, const char *value) {
        tag->removeFrames(id);
        auto *f = new ID3v2::TextIdentificationFrame(id, String::UTF8);
        f->setText(String(value, String::UTF8));
        tag->addFrame(f);
    };
    set("TIT2", "Fixture Title");
    set("TPE1", "Fixture Artist");
    set("TALB", "Fixture Album");
    set("TPE2", "Fixture Album Artist");
    set("TCOM", "Fixture Composer");
    set("TCON", "Rock");
    set("TDRC", "2021-03-04");
    set("TRCK", "3/12");
    set("TPOS", "1/2");
}

static FLAC::Picture *flacPicture(const ByteVector &data, const char *mime, int w, int h) {
    auto *p = new FLAC::Picture();
    p->setType(FLAC::Picture::FrontCover);
    p->setMimeType(mime);
    p->setDescription("Front");
    p->setData(data);
    p->setWidth(w);
    p->setHeight(h);
    p->setColorDepth(24);
    return p;
}

int main(int argc, char **argv) {
    if (argc < 6) {
        std::fprintf(stderr, "usage: fixturetool <kind> <file> <cover.png> <cover.jpg> <marker>\n");
        return 2;
    }
    const std::string kind = argv[1];
    const char *path = argv[2];
    const ByteVector png = readFile(argv[3]);
    const ByteVector jpg = readFile(argv[4]);
    const std::string marker = argv[5];
    bool ok = false;

    if (kind == "mp3v23" || kind == "mp3v24") {
        MPEG::File f(path);
        ID3v2::Tag *tag = f.ID3v2Tag(true);
        addUnknownFrames(tag, marker);
        addID3Extras(tag);
        if (kind == "mp3v24") {
            // legacy grouping stored in TIT1 (no GRP1) and an APE tag next to ID3v2
            auto *tit1 = new ID3v2::TextIdentificationFrame("TIT1", String::UTF8);
            tit1->setText("Legacy Grouping");
            tag->addFrame(tit1);
            APE::Tag *ape = f.APETag(true);
            ape->setItem("Title", APE::Item("Title", StringList("Fixture Title")));
            ape->setItem("MLTEST_APE", APE::Item("MLTEST_APE", StringList(String(marker + "-APE"))));
            ok = f.save(MPEG::File::ID3v2 | MPEG::File::APE | (f.hasID3v1Tag() ? MPEG::File::ID3v1 : 0),
                        File::StripNone, ID3v2::v4, File::DoNotDuplicate);
        } else {
            ok = f.save(MPEG::File::ID3v2 | (f.hasID3v1Tag() ? MPEG::File::ID3v1 : 0), File::StripNone, ID3v2::v3,
                        File::DoNotDuplicate);
        }
    } else if (kind == "m4a") {
        MP4::File f(path);
        MP4::Tag *t = f.tag();
        t->setItem("\251xyz", MP4::Item(StringList(String(marker + "-XYZ"))));  // not mapped by TagLib
        t->setItem("----:com.apple.iTunes:MLTEST_CUSTOM", MP4::Item(StringList(String(marker + "-CUSTOM"))));
        ok = f.save();
    } else if (kind == "ogg" || kind == "opus" || kind == "spx" || kind == "oga") {
        Ogg::XiphComment *x = nullptr;
        std::unique_ptr<File> file;
        if (kind == "ogg") { auto *v = new Ogg::Vorbis::File(path); x = v->tag(); file.reset(v); }
        if (kind == "opus") { auto *v = new Ogg::Opus::File(path); x = v->tag(); file.reset(v); }
        if (kind == "spx") { auto *v = new Ogg::Speex::File(path); x = v->tag(); file.reset(v); }
        if (kind == "oga") { auto *v = new Ogg::FLAC::File(path); x = v->tag(); file.reset(v); }
        x->addPicture(flacPicture(png, "image/png", 16, 16));
        x->addField("MLTEST_CUSTOM", String(marker + "-CUSTOM"));
        ok = file->save();
    } else if (kind == "wav") {
        RIFF::WAV::File f(path);
        ID3v2::Tag *tag = f.ID3v2Tag();
        setBasicID3(tag);
        addUnknownFrames(tag, marker);
        tag->addFrame(picture(jpg, "image/jpeg", 3, "Cover"));
        ok = f.save(RIFF::WAV::File::AllTags, File::StripNone, ID3v2::v3);
    } else if (kind == "aiff") {
        RIFF::AIFF::File f(path);
        addUnknownFrames(f.tag(), marker);
        ok = f.save(ID3v2::v4);
    } else if (kind == "wma") {
        ASF::File f(path);
        ASF::Picture p;
        p.setType(ASF::Picture::FrontCover);
        p.setMimeType("image/png");
        p.setDescription("Front");
        p.setPicture(png);
        f.tag()->addAttribute("WM/Picture", ASF::Attribute(p));
        ok = f.save();
    } else if (kind == "wv") {
        WavPack::File f(path);
        ByteVector data("cover.png");
        data.append('\0');
        data.append(png);
        f.APETag(true)->setItem("Cover Art (Front)", APE::Item("Cover Art (Front)", data, true));
        ok = f.save();
    } else if (kind == "tta" || kind == "dsf" || kind == "dff") {
        ID3v2::Tag *tag = nullptr;
        std::unique_ptr<File> file;
        if (kind == "tta") { auto *t = new TrueAudio::File(path); tag = t->ID3v2Tag(true); file.reset(t); }
        if (kind == "dsf") { auto *t = new DSF::File(path); tag = t->tag(); file.reset(t); }
        if (kind == "dff") { auto *t = new DSDIFF::File(path); tag = t->ID3v2Tag(true); file.reset(t); }
        setBasicID3(tag);
        addUnknownFrames(tag, marker);
        tag->addFrame(picture(png, "image/png", 3, "Cover"));
        ok = file->save();
    } else {
        std::fprintf(stderr, "unknown kind %s\n", kind.c_str());
        return 2;
    }
    if (!ok) {
        std::fprintf(stderr, "saving %s failed\n", path);
        return 1;
    }
    return 0;
}
