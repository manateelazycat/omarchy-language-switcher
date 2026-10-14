// Test-only QML instrumentation; run with Qt's offscreen clipboard.
#include <QClipboard>
#include <QCoreApplication>
#include <QFile>
#include <QGuiApplication>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QMimeData>
#include <QQmlExtensionPlugin>
#include <QQuickItem>
#include <QUrl>
#include <signal.h>

class LazyText : public QMimeData {
public:
    explicit LazyText(int *reads) : reads(reads) {}
    QStringList formats() const override { return {QStringLiteral("text/plain")}; }
    bool hasFormat(const QString &type) const override { return type == QStringLiteral("text/plain"); }
protected:
    QVariant retrieveData(const QString &, QMetaType type) const override {
        ++*reads;
        return type == QMetaType::fromType<QString>() ? QVariant(QStringLiteral("English"))
                                                     : QVariant(QByteArray("English"));
    }
private:
    int *reads;
};

class SearchProbe : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    ~SearchProbe() override { QGuiApplication::clipboard()->clear(); }
    Q_INVOKABLE void offerText() {
        reads = 0;
        QGuiApplication::clipboard()->setMimeData(new LazyText(&reads));
    }
    Q_INVOKABLE int payloadReads() const { return reads; }
    Q_INVOKABLE void key(QQuickItem *item, int key, int modifiers = 0, const QString &text = {}) {
        QKeyEvent press(QEvent::KeyPress, key, Qt::KeyboardModifiers(modifiers), text);
        QCoreApplication::sendEvent(item, &press);
        QKeyEvent release(QEvent::KeyRelease, key, Qt::KeyboardModifiers(modifiers), text);
        QCoreApplication::sendEvent(item, &release);
    }
    Q_INVOKABLE void preedit(QQuickItem *item, const QString &text) {
        QInputMethodEvent event(text, {});
        QCoreApplication::sendEvent(item, &event);
    }
    Q_INVOKABLE void commit(QQuickItem *item, const QString &text) {
        QInputMethodEvent event;
        event.setCommitString(text);
        QCoreApplication::sendEvent(item, &event);
    }
    Q_INVOKABLE bool writeFile(const QUrl &url, const QString &text) {
        QFile file(url.toLocalFile());
        return file.open(QIODevice::WriteOnly | QIODevice::Truncate) && file.write(text.toUtf8()) >= 0;
    }
    Q_INVOKABLE QString readFile(const QUrl &url) {
        QFile file(url.toLocalFile());
        return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
    }
    Q_INVOKABLE bool alive(int pid) const { return pid > 0 && ::kill(pid, 0) == 0; }
private:
    int reads = 0;
};

class SearchTestPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        qmlRegisterType<SearchProbe>(uri, 1, 0, "SearchProbe");
    }
};

#include "search_probe.moc"
