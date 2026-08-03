# Post-Change Engineering Audit

Diese Vorlage kann nach einem Fix, Refactoring, Release-Kandidaten oder einer
Gruppe zusammenhängender Commits direkt in Codex eingefügt werden.

## Kopiervorlage

```text
Führe einen vollständigen Post-Change Engineering Audit aller Änderungen von
<BASELINE> bis <TARGET> durch. Falls <TARGET> nicht angegeben ist, verwende
HEAD. Ermittle den tatsächlichen Diff und seine Abhängigkeiten selbstständig.

Prüfe insbesondere:

1. Funktionale Korrektheit und erwartetes Laufzeitverhalten.
2. Blast Radius: alle direkt und indirekt betroffenen Komponenten, Zustände,
   Schnittstellen, Konfigurationen und Nutzerabläufe.
3. Kausalzusammenhänge: Welche Änderung verursacht welches Verhalten oder
   welche mögliche Nebenwirkung?
4. Regressionen in allen unterstützten Varianten, Versionen und UI-Zuständen.
5. Synchronität zwischen kanonischen Quellen, generierten oder vendorten
   Kopien und lokal installierten Artefakten.
6. Installations-, Update-, Migrations-, Neustart- und Rollback-Verhalten.
7. Bindings, Zustandslebenszyklen, Animationen, Layoutstabilität, Eingabe,
   Performance und Runtime-Logs.
8. Testabdeckung, Aussagekraft der Tests und fehlende Grenzfälle.
9. Abhängigkeiten, Herkunft externer Artefakte sowie Release- und
   Supply-Chain-Risiken, sofern der Diff diese Bereiche berührt.

Belege jede Feststellung mit Datei und Zeile, Testausgabe, Runtime-Log,
Screenshot oder reproduzierbarem Verhalten. Trenne bestätigte Fehler,
plausible Risiken und reine Vermutungen deutlich voneinander. Ein bestandener
Test allein ist kein Beweis, wenn er nicht die betroffene Eigenschaft prüft.

Bewerte jedes Finding als Critical, High, Medium, Low oder Informational und
nenne Root Cause, Auswirkungen, Blast Radius sowie einen konkreten Fix oder
eine Verifikationsmaßnahme. Verändere zunächst keinen Code und erstelle keinen
Commit. Schließe mit einer Go/No-Go-Empfehlung, den verbleibenden Restrisiken
und einer Liste aller ausgeführten Prüfungen ab.

Projektregeln:

- Behandle <REFERENZ-REPOSITORY> ausschließlich als Referenz und vermische es
  nicht mit <ZIEL-REPOSITORY>.
- Bewahre bestehende Benutzeränderungen und untersuche nur den angegebenen
  Scope.
- Behebe bestätigte Findings erst nach meinem Review des Audit-Berichts.
```

## Shibumi-Beispiel

Für die aktuell noch nicht gepushten Shibumi-Änderungen:

```text
Führe den Post-Change Engineering Audit aus ENGINEERING_AUDIT.md für alle
Änderungen von a32b784^ bis HEAD durch. Das Ziel-Repository ist Shibumi-Shell.
quickshell-dots darf nur als Referenzquelle verwendet und nicht mit
Shibumi-Shell vermischt werden. Verändere während des Audits keinen Code.
```

`<BASELINE>` sollte der letzte bekannte stabile Commit oder Tag sein.
`<TARGET>` ist meistens `HEAD`. Bei einem einzelnen Commit kann als Scope
beispielsweise `HEAD^` bis `HEAD` verwendet werden.
