# Prüffälle Kartenterminal-Zugang

`genius-code-faelle.json` ist eine byte-gleiche Kopie aus dem Backend
(`functions-kasse/test/unit/fixtures/genius-code-faelle.json`). Sie ist der
Vertrag zwischen `genius-core.codeAusEingabe` dort und `parseTerminalCode`
hier: beide Seiten laufen jeden Fall. Geändert wird nur im Backend, dann hier
neu kopiert, nie von Hand angepasst, um einen Test grün zu bekommen.
