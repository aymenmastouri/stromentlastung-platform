# Stromentlastung – Referenzverfahren

Ein Fachverfahren-typisches Referenzverfahren für die Steuerentlastung für Unternehmen nach § 9b StromStG: Unternehmen des Produzierenden Gewerbes und der Land- und Forstwirtschaft beantragen die Entlastung der Stromsteuer für betrieblich entnommenen Strom, das Hauptzollamt prüft, setzt fest, zahlt aus und fordert nach einer Prüfung zurück. Nachgebaut und bewusst vereinfacht, in seinen Regeln belastbar; kein Verfahren der Zollverwaltung, kein Echtbetrieb.

Dieses Repository hält, was keinem Dienst gehört: das [Fachkonzept](docs/fachkonzept.md) (Rechtsstand 31. Dezember 2025, jede Regel mit Fundstelle), die [Architektur mit Bauplan](docs/architektur.md), den Keycloak-Realm, die Compose-Datei, die Gateway-Konfiguration und den Fahrstand.

## Repositories

| Repository | Verantwortung | Erreichbar |
| --- | --- | --- |
| `stromentlastung-platform` | Fachkonzept, Architektur, Realm, Compose, Gateway, Fahrstand | Keycloak `localhost:9091` |
| `stromentlastung-unternehmen` | Unternehmensregister: Stammdaten, Zuständigkeit, Zuordnung nach § 15 StromStV | `localhost:8091/api/unternehmen` |
| `stromentlastung-antrag` | Vorgang: Antrag, Rechenkern, Fristen, Zustandsmaschine, Vorgangsprotokoll | `localhost:8092/api/antraege` |
| `stromentlastung-bescheid` | Bescheide: Textbausteine, PDF, Bekanntgabe, Postfach | `localhost:8093/api/bescheide` |
| `stromentlastung-zahlung` | Erhebung: Auszahlung, Rückforderung, Säumniszuschläge | `localhost:8094/api/zahlungen` |
| `stromentlastung-ui` | Antragsportal und Fachanwendung in einer Oberfläche | `localhost:4202` |
| `stromentlastung-e2e` | Ende-zu-Ende-Tests mit Playwright und axe | — |

Alle sieben liegen nebeneinander in einem Arbeitsbereich; der Fahrstand und die Compose-Datei setzen diese Anordnung voraus.

## Betrieb

```bash
scripts/stromentlastung.sh start     # Keycloak (Compose), vier Dienste (JDK 17, Maven-Wrapper), Oberfläche
scripts/stromentlastung.sh status
scripts/stromentlastung.sh stop
scripts/stromentlastung.sh reset     # stop und H2-Dateien löschen; der nächste Start sät neu
```

Voraussetzungen: Docker, JDK 17, Node 22. Der erste Start lädt Maven und die Abhängigkeiten und dauert entsprechend; danach sind die Dienste in unter einer Minute oben. Jeder Dienst hält seine H2-Datenbank im Dateimodus unter `./data/` seines Repositories; die Saatdaten-Geschichten aus Fachkonzept Kap. 12 werden von Flyway eingespielt.

Containerbetrieb: `docker compose --profile full up --build` baut alles und stellt den Stapel hinter nginx auf `localhost:8090` bereit.

## In die Datenbanken schauen

Jeder Dienst öffnet bei laufendem Betrieb seine H2-Konsole unter dem Kontextpfad, etwa `http://localhost:8094/api/zahlungen/h2-console` (entsprechend `8091/api/unternehmen`, `8092/api/antraege`, `8093/api/bescheide`). JDBC-URL wie im Dienst, `jdbc:h2:file:./data/zahlung;AUTO_SERVER=TRUE`, Benutzer `sa`, kein Passwort. Dort lässt sich der Schutz des Vorgangsprotokolls vorführen: ein `UPDATE` oder `DELETE` auf `vorgangsereignis` im Vorgangsdienst lehnt der Trigger ab. Wer lieber ein Werkzeug wie IntelliJ oder DBeaver nutzt, verbindet sich mit derselben URL über den absoluten Pfad der Datei; `AUTO_SERVER` erlaubt den Parallelzugriff bei laufendem Dienst.

## Konten

Alle Passwörter lauten `stromentlastung`. Unternehmen: `nordfeld@stromentlastung.dev` (Nordfeld Metallbau, Regelfall), `ostsee-werft@stromentlastung.dev` (offene Rückforderung), `elbtal@stromentlastung.dev` (Rückfrage), `weserland@stromentlastung.dev` (Entwurf für 2026) und die übrigen aus Architektur Kap. 4. Hauptzollamt Nord: `mastouri@` (Sachbearbeitung und Zeichnung), `wagner@` und `demir@` (Sachbearbeitung), `becker@` (Zeichnung), `roth@` (Prüfdienst); Hauptzollamt Süd: `keller@` (Sachbearbeitung), `vogt@` (Zeichnung).

## Was die Saat zeigt

Dreizehn Vorgänge in zwölf Zuständen: ein ausgezahlter Regelfall mit Bescheid, eine Ablehnung genau am Selbstbehalt, ein Antrag zum alten Satz von 2023, eine Ablehnung wegen Festsetzungsverjährung, ein Entwurf für 2026, eine laufende Rückfrage, eine offene Rückforderung mit laufenden Säumniszuschlägen nach Außenprüfung, ein durch die Beihilfeversicherung gesperrter Entwurf, eine abgelehnte Zuordnung, ein landwirtschaftlicher Betrieb, ein Vorgang in der Freigabe mit Nutzenergie-Abzug, ein frischer Eingang und eine Rücknahme.
