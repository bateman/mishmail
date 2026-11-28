# Client Gmail per macOS — Registro delle decisioni

Versione: 0.49
Ultimo aggiornamento: 28 novembre 2026
Stato: documento in evoluzione

## 1. Obiettivo

Sviluppare un client e-mail desktop per macOS, dedicato esclusivamente agli account Gmail, capace di riprodurre il più fedelmente possibile l'esperienza di Gmail con un'interfaccia e un comportamento nativi per macOS.

## 2. Decisioni confermate

| ID | Decisione | Motivazione |
|---|---|---|
| DEC-001 | **Solo macOS** | Non è più richiesta la compatibilità con Windows e Linux. |
| DEC-002 | **Solo account Gmail** | Non è necessario supportare provider IMAP generici. |
| DEC-003 | **Gmail API anziché IMAP/SMTP** | Accesso diretto a thread, label, loro colori, filtri e cronologia delle modifiche di Gmail. |
| DEC-004 | **Sviluppo ed esecuzione fuori dal Mac App Store** | È possibile avviare l'app con Xcode e utilizzarla localmente come `.app`. |
| DEC-005 | **Accesso con Google e sessione persistente** | OAuth 2.0 con refresh token; evitare autenticazioni ripetute durante lo sviluppo. |
| DEC-006 | **Linguaggio non vincolante** | La tecnologia viene scelta in funzione dell'obiettivo e della piattaforma. |
| DEC-007 | **Approccio fork + riuso selettivo** | Usare **MishMail come candidato principale per il fork** e **Postie come fonte di funzionalità e test**. Decisione di indirizzo, subordinata all'audit dei repository e alla compilazione delle due applicazioni. Dalla v0.7 il ruolo di Postie è ridimensionato: ICS/RSVP esiste già nel fork (sezione 8.2). |
| DEC-008 | **Security-first prima di importare funzionalità** | Risolvere i rischi prioritari dell'audit sul fork; effettuare test nativi macOS prima di collegare account reali o distribuire build. |
| DEC-009 | **Aggiornamenti automatici sospesi nel fork di sviluppo** | Disabilitare la sostituzione automatica di eseguibili finché non siano definiti canale di release, identità del publisher e controlli anti-rollback. Dalla v0.7 è un prerequisito per l'uso con account reali, non solo per la distribuzione: l'updater parte da solo anche sulle build locali (sezione 13). Implementato nello step 1A (PR #7): updater inerte senza canale e comunque spento su una copia senza Team ID. |
| DEC-010 | **GO su MishMail come base** | Decisione del 23 novembre 2026, dopo la CI verde sul commit auditato. Postie resta un riferimento di confronto. |
| DEC-011 | **AI e server MCP spenti per il momento** | Estranei all'obiettivo della sezione 1 e sede di quattro finding. Il codice resta; un'impostazione di build li riaccende (`MISHMAIL_AI_FEATURES`, step 2A). |
| DEC-012 | **Notion Mail fuori dal prodotto** | Non interessa: rimossi la funzione di migrazione e ogni riferimento (PR #11). |
| DEC-013 | **La rimozione di un account cancella sempre tutto ciò che gli appartiene** | Nessuna richiesta su cosa conservare: più semplice e più sicuro (step 2B). |
| DEC-014 | **Notifiche generiche come impostazione predefinita** | "New mail" senza mittente né oggetto; mittente e oggetto solo se attivati dall'utente (step 2B). |
| DEC-015 | **Messaggio d'errore di Gmail limitato a 160 caratteri** | L'avviso mantiene il messaggio leggibile di Google, accettando che possa riportare parte della richiesta, per esempio una ricerca; il JSON grezzo e gli altri campi restano fuori (PR #10). |
| DEC-016 | **F-01 segnalato all'upstream dal proprietario** | La segnalazione riservata secondo `SECURITY.md` è a carico del proprietario del fork. |
| DEC-017 | **Shortcut predefiniti come Gmail Web** | I tasti predefiniti seguono Gmail sul web e restano personalizzabili; dove Gmail confligge con una convenzione di macOS vince macOS (PR #17). |
| DEC-018 | **Apertura nel pannello di lettura come predefinito** | In Settings → Appearance → "Opening a conversation" il predefinito è "Shows in a reading pane"; una scelta salvata viene rispettata (PR #17). |
| DEC-019 | **Cancellato vuol dire sparito** | Ciò che viene cancellato non deve più esistere, non solo risultare irraggiungibile: sovrascrittura nel database e nell'indice di ricerca, pulizia del file di appoggio, rimozione di allegati e notifiche con il messaggio. I limiti fisici (SSD, backup, istantanee) sono dichiarati in `SECURITY.md` (PR #18). |
| DEC-020 | **Chat AI alla rimozione di un account: regola prudente** | Rimuovere un account cancella ogni chat che ha usato uno strumento e tutte quelle prive di tracciatura. Confermato dal proprietario. |
| DEC-021 | **Icone monocromatiche** | Le icone di navigazione (barra laterale, impostazioni, intestazione della lista) sono in scala di grigi come in Gmail; il colore resta solo dove porta informazione: colori delle label, stella, badge, avvisi (PR #20). |
| DEC-022 | **Correttore in più lingue insieme** | Si usano i dizionari di macOS, senza cambiare impostazioni di sistema. Con più lingue scelte una parola è sottolineata solo se sbagliata in tutte; il costo accettato è che un refuso valido in un'altra lingua scelta non viene segnalato (PR #22). |
| DEC-023 | **Colori delle label come in Gmail** | Il colore di una label è quello di Gmail, aggiornato a ogni sincronizzazione; fondo pieno e testo sempre leggibile. Un colore scelto nell'app ha la precedenza e non viene scritto su Gmail. Le label senza colore sono grigio neutro (PR #25). |
| DEC-024 | **Stile di comunicazione conciso** | Tutte le sessioni di lavoro sul repository comunicano in modo conciso, secondo `CLAUDE.md`; errori, passi saltati e cose non verificate si dichiarano sempre (PR #24). |
| DEC-025 | **Colore della label dell'account** | Ogni account ha un colore locale per la sua label, scelto con il selettore di colore di sistema; non viene inviato a Google e viene cancellato con l'account (PR #31). |
| DEC-026 | **Foto profilo Google** | L'avatar dell'account è la foto profilo Google, ottenuta senza nuovi permessi, scaricata solo da host Google senza token, conservata nel database cifrato e cancellata con l'account (PR #32). |
| DEC-027 | **Warning come errori in CI** | La CI fallisce su qualsiasi warning di compilazione nel codice dell'app e dei test di unità, ed esegue i test degli script e `shellcheck`; le build locali e di rilascio non cambiano (PR #33). |
| DEC-028 | **Icone della barra laterale** | Le icone seguono la dimensione della barra laterale impostata in macOS e non usano mai il colore d'accento (PR #34). La questione della capsula di selezione standard, rimasta in attesa di conferma, è superata da DEC-035: il proprietario ha chiesto un colore d'accento configurabile. |
| DEC-029 | **Forma delle label come in Gmail** | Le label sono rettangoli arrotondati compatti nel colore della label, senza contorno sulle righe normali; il contorno resta solo per colori quasi invisibili sullo sfondo, sulla selezione quando la label vi si confonderebbe e sui pallini di colore. Le label senza colore sono grigio neutro (PR #37). |
| DEC-030 | **Colore dell'account come anello, label come titolo** | Il colore della label dell'account è un anello intorno alla foto (spessore 3 pt, raddoppiato su richiesta) e il nome della label sostituisce il nome del mittente come titolo dell'account; la pillola dell'account è rimossa. Nei punti visibili ai destinatari resta il nome del mittente (PR #36, #41). |
| DEC-031 | **Messaggi di un thread come in Gmail** | Nel pannello di lettura i messaggi di una conversazione sono righe piatte a tutta larghezza separate da un filetto, non schede (PR #38). |
| DEC-032 | **Cache persistente e cifrata delle immagini incorporate** | "Sì, è necessaria": le immagini incorporate (`cid:`) già risolte restano nel database cifrato tra un avvio e l'altro, entro 200 MiB, e spariscono con messaggio, thread e account secondo DEC-019 (PR #39, migrazione v54). |
| DEC-033 | **Immagini remote caricate per impostazione predefinita** | Il predefinito di "Load remote images" è caricarle, con due limiti approvati: si caricano solo all'apertura del messaggio, mai in anticipo per i vicini, e la posta in Spam resta bloccata. Una scelta salvata viene rispettata; "Ask each time" e "VIP senders" restano disponibili. Costo accettato: il mittente apprende apertura, indirizzo IP e client (PR #40). |
| DEC-034 | **Cache delle immagini remote solo dove sono già permesse** | Le immagini remote entrano nella cache cifrata solo per i messaggi in cui il caricamento è già consentito; stesse regole di cancellazione di DEC-019 e DEC-032 (PR #42, migrazione v55, in lavorazione). |
| DEC-035 | **Colore d'accento configurabile** | Il colore d'accento dell'app si sceglie con il selettore di colore di sistema in Settings → Appearance; "Default" mantiene l'aspetto precedente. Il testo sull'accento resta leggibile (bianco o nero); la riga selezionata nel colore scelto vale solo su macOS 26 e successivi (PR #43). Supera la questione lasciata aperta in DEC-028. |
| DEC-036 | **Modifiche semplici senza review** | Quando il proprietario qualifica una richiesta come semplice, la esegue una sessione Sonnet, senza `ponytail-review` né `security-audit`, e la PR si unisce in `main` a CI verde. La scorciatoia non si applica per iniziativa dell'orchestratore (prima applicazione: PR #41). |
| DEC-037 | **Processo: archiviazione, branch, subentro** | Una sessione che ha finito senza nulla di pendente viene archiviata subito dall'orchestratore; non si chiede di cancellare i branch, che GitHub elimina all'unione. Il 24 novembre 2026 il proprietario ha sostituito l'orchestratore con una nuova sessione, a cui sono state passate tutte le istruzioni di processo. |
| DEC-038 | **Livelli di review** | Tre livelli, scritti in `CLAUDE.md`: modifica semplice (una proprietà, un colore): Sonnet, nessuna review, unione diretta in `main` senza attendere la CI; lavoro non complesso e a basso rischio di sicurezza: Sonnet, solo `ponytail-review`, PR regolare; tutto il resto: Opus con entrambe le review. `ponytail-review` gira in modalità `full`, non più `ultra`. Sostituisce DEC-036 (PR #46). |
| DEC-039 | **Segnalazione di F-01 all'upstream annullata** | Il proprietario ha tolto il compito: F-01 non viene segnalato all'upstream. Nel fork resta mitigato con l'updater spento (DEC-009). Sostituisce DEC-016. |
| DEC-040 | **Ondata 3 avviata** | Avviata dal proprietario il 25 novembre 2026 senza attendere il completamento del cancello; le verifiche su Mac e su account reale restano da fare PR per PR. |
| DEC-041 | **Snooze: variante B** | Il modello resta quello locale (conversazione archiviata su Gmail e risvegliata da MishMail aperto), reso corretto; in più le conversazioni posticipate su Gmail da web o telefono compaiono in "Snoozed" anche sul Mac, senza orario. Alla rimozione di un account le conversazioni posticipate da MishMail tornano in Inbox prima della cancellazione (PR #47). |
| DEC-042 | **Google Calendar: perimetro B** | Disponibilità accanto all'invito, risposta scritta sul calendario, "aggiungi al calendario", con un secondo consenso Google separato. Agenda, promemoria ed eventi da un messaggio (perimetri C e D) restano lavoro futuro. |
| DEC-043 | **Immagini remote: prima apertura come oggi** | Alla prima apertura le immagini si caricano dal vivo e l'app le salva in secondo piano per le aperture successive; costo accettato: due richieste al mittente alla prima apertura. La variante a richiesta singola resta un seguito (PR #42). |
| DEC-044 | **Ondata 4 avviata** | Avviata dal proprietario il 25 novembre 2026 in parallelo all'ondata 3. |
| DEC-045 | **PGP: perimetro B** | Verifica delle firme, decifratura e import manuale delle chiavi. Invio firmato o cifrato, generazione di chiavi, ricerca di chiavi in rete e Autocrypt (perimetri C e D) restano lavoro futuro. La libreria crittografica si adotta solo con il sì esplicito del proprietario. |
| DEC-046 | **Calendari per i conflitti scelti dall'utente** | Per ogni account l'utente sceglie quali calendari contano per disponibilità e conflitti; il principale è selezionato per impostazione predefinita. |
| DEC-047 | **Libreria OpenPGP: rPGP (Rust), se non esiste una soluzione già pronta** | Sì a rPGP, a condizione che la sessione verifichi prima che non esista una soluzione già pronta all'uso (ad esempio una libreria in Swift). Se ne esiste una adeguata, decide il proprietario. Motivo della preferenza per Rust rispetto a Go: nessun runtime nell'app e chiavi azzerabili in memoria. GnuPG scartato: programma esterno, incompatibile con la sandbox e con "cancellato vuol dire sparito". |
| DEC-048 | **Calendar: permesso ampio** | A Google si chiede `calendar.events`: lettura e scrittura sugli eventi di tutti i calendari, condivisi inclusi, così i conflitti mostrano anche i titoli dei calendari condivisi. Scartata l'alternativa stretta (solo eventi propri più libero/occupato). |
| DEC-049 | **Risposta agli inviti: sempre calendario più e-mail** | Con Calendar collegato la risposta va sul calendario (senza notifiche di Google) e sempre anche per e-mail all'organizzatore. Sostituisce la regola "solo calendario per gli organizzatori Google": i segnali per riconoscerli sono scritti dal mittente e un invito falsificato sarebbe risultato accettato senza avvisare l'organizzatore. Decisione dell'orchestratore dopo le review della PR #55, comunicata al proprietario, ribaltabile dopo la prova con account reali. |
| DEC-050 | **Libreria OpenPGP in un repository separato** | La libreria rPGP compilata sta nel repository `bateman/dreamail-openpgp`, creato dal proprietario; MishMail la fissa per versione e checksum come già fa con GRDB. Scartata la compilazione in CI da `Vendor/`, che avrebbe richiesto di modificare il controllo `check-package-pins`. La verifica delle alternative richiesta da DEC-047 è fatta: nessuna soluzione Swift o Objective-C pronta è adeguata (tabella con le fonti nella PR #56). |
| DEC-051 | **OpenPGP: chiavi Ed448/X448 rifiutate** | Chiavi, firme e messaggi Ed448/X448 risultano "non supportati": la dipendenza che li implementa (`cx448`) si dichiara non verificata e non pubblica un testo di licenza, e non si può togliere dalla compilazione di rPGP 0.21.1. Rifiutati anche MD5, RIPEMD-160 e SHA-1 nelle firme dei messaggi. Due avvisi sui tempi di calcolo (RUSTSEC-2023-0071 su `rsa`, RUSTSEC-2026-0387 su `crypto-bigint`) sono accettati come limiti noti, senza correzione disponibile per rPGP 0.21.1. Decisione dell'orchestratore, comunicata al proprietario, ribaltabile. |
| DEC-052 | **Risposta agli inviti: prima l'e-mail, poi il calendario** | Con Calendar collegato l'e-mail di risposta parte per prima; il calendario viene scritto solo dopo, e un suo errore produce solo un avviso. Precisa DEC-049. |
| DEC-053 | **Badge dei non letti sulla foto profilo** | Ogni foto profilo nel selettore degli account mostra i non letti del suo account, nell'angolo in alto a destra, anche sopra l'anello colorato; stesso criterio del badge del Dock; tetto "99+"; nessun badge sulla voce "tutti gli account". |
| DEC-054 | **Nel dubbio, come fa Gmail** | Quando una richiesta lascia aperta una scelta e serve un'assunzione, si prende il comportamento di Gmail (prima il web) e la si dichiara nel messaggio che avvia il lavoro, senza fermarsi a chiedere. Le decisioni già registrate che si scostano da Gmail di proposito restano valide. Regola scritta anche in `CLAUDE.md`. |
| DEC-055 | **Firme per account** | Più firme con nome per account, una predefinita per i nuovi messaggi e una per risposte e inoltri; nel database cifrato, cancellate con l'account; "Importa da Gmail" copia la firma di Gmail senza riscriverla su Gmail; in composizione la firma del mittente entra da sola, segue il cambio di mittente se non è stata modificata a mano, e si sceglie da un menu che include "Nessuna firma". |
| DEC-056 | **Impostazioni per account** | "Show sender and subject in notifications" diventa un'impostazione di ciascun account: gli account esistenti ereditano il valore globale, i nuovi partono spenti (DEC-014). I filtri Gmail si vedono e si modificano per account. |
| DEC-057 | **Barra laterale come Gmail e barra degli account** | La barra laterale segue Gmail: viste di sistema nel suo ordine, riga "More", sezione "Labels" con le label ad albero; ciò che è solo di MishMail (Reminders, Outbox, viste salvate) trova posto sotto "More" o in una sezione "Views". A sinistra una barra degli account sempre visibile, di colore fisso (non l'accent) diverso in modalità chiara e scura, con le foto profilo e i non letti per account; in basso Settings e, in futuro, altri collegamenti. |
| DEC-058 | **`make run` con l'account reale** | `DEMO=0` è il predefinito; la casella finta resta per i test di interfaccia e per chi la chiede con `DEMO=1`. Il codice del demo non viene tolto. |
| DEC-059 | **Rilasci della libreria OpenPGP** | Il workflow "Release" di `bateman/dreamail-openpgp` può essere lanciato dall'orchestratore. La libreria si compila senza LTO, perché gli oggetti in bitcode di Rust non sono leggibili da Xcode. |
| DEC-060 | **Libreria OpenPGP collegata anche a interruttore spento** | Con `MISHMAIL_PGP` spento la libreria resta collegata nell'app e la tabella delle chiavi esiste vuota; il comportamento non cambia e nessuna voce PGP è visibile. Dopo la verifica del funzionamento si valuta il caricamento dinamico, con un'opzione che da spenta non carica la libreria. |
| DEC-061 | **Nomi del rebranding a DreaMail** | Decisi i nomi, non ancora la data: MishMail → DreaMail (D e M maiuscole; `dreamail` in percorsi e URL, `DREAMAIL_` per interruttori e variabili), prefisso C `mm_` → `dm_`, libreria `MishMailRPGP` → `DreaMailRPGP`, "Ask Mish" → "Ask AI". Le funzioni AI e MCP restano nel codice, spente (DEC-011): serviranno per il completamento delle e-mail e la riscrittura delle bozze. Studio in `docs/studi/rebranding-dreamail.md`. |
| DEC-062 | **Chat e Calendar integrati: solo studio per ora** | Chat di Gmail e Google Calendar completo non si costruiscono finché il client di posta non è completo e stabile per l'uso quotidiano. Studi in `docs/studi/google-chat.md` e `docs/studi/google-calendar.md`. |
| DEC-063 | **Barra laterale come Gmail: scostamenti** | Spam mostra solo ciò che il Mac ha (spam arrivato dopo l'aggiunta dell'account o segnalato dall'app): lo spam più vecchio resta su Gmail. La vista di tutte le etichette esce dalla barra laterale e resta su `g l`, Go ▸ Labels e palette. "Purchases" di Gmail non è offerta: l'API non ha quell'etichetta. Outbox e Reminders restano visibili fuori da "More" quando non sono vuoti. |
| DEC-064 | **OpenPGP: regole di fiducia e formati** | Una chiave si salva solo dopo una conferma che mostra impronta e tutti gli indirizzi dichiarati; un indirizzo già coperto da un'altra chiave è segnalato. Una copia più vecchia non annulla una revoca né una scadenza: per importare una chiave rinnovata si elimina prima quella scaduta, finché la libreria non fonde i certificati. Ogni decifratura fallita ha lo stesso testo e lo stesso colore: "non supportato" e "danneggiato" non sono verdetti autenticati. La libreria decifra il formato OCB di GnuPG 2.4 (pacchetto 20), che è cifratura autenticata; il resto della politica (DEC-051) non cambia. |
| DEC-065 | **Rebranding a DreaMail: si fa** | Rinomina completa in una volta, identificativi del bundle compresi (opzione A dello studio), senza migrazione automatica: non ci sono dati solo locali da salvare, l'accesso si rifà. "Support MishMail" e il file delle donazioni verso l'autore originale sono rimossi; l'attribuzione e il copyright dell'autore originale restano. Il nome è libero per quanto verificato: esiste solo "DreamMail" con due m. Forme derivate come nella sezione 9 dello studio (bundle `io.github.bateman.DreaMail`, repository `bateman/dreamail`). Ordine: libreria v0.2.0 con i nomi nuovi, poi una PR di rinomina nell'app, poi rinomina del repository e reinstallazione da parte del proprietario. |
| DEC-066 | **Chat: account personali** | Gli account del proprietario sono personali (@gmail.com). La Chat API richiede Workspace per essere attivata e il supporto agli account personali non è documentato: per ora solo il collegamento a Chat nel browser dalla barra degli account; la chat nativa resta subordinata a una prova. |
| DEC-067 | **Calendar: solo il pannello come in Gmail** | L'obiettivo è il pannello a destra della posta (passi 1–3 dello studio: ciò che c'è già, agenda in sola lettura, promemoria). La finestra calendario completa e i task non sono in programma. |
| DEC-068 | **Difetto di rPGP da segnalare a monte** | Il sottoflusso in `aead_setup_rfc9580` (rPGP 0.21.1) è descritto nell'issue 8 di `bateman/dreamail-openpgp`; la segnalazione agli sviluppatori di rPGP la fa il proprietario. |
| DEC-069 | **Rinomina in DreaMail eseguita** | Applicati i nomi di DEC-061 e DEC-065 in una sola PR (`chore/rename-dreamail`), con uno script di sostituzioni esatte (nel corpo della PR #73, tolto dal repository a lavoro finito) e una revisione a mano; libreria OpenPGP fissata a `v0.2.0` (commit `b87eb51`), che cambia solo i nomi (`DreaMailRPGP`, `dm_pgp_*`). Nessuna migrazione: le chiavi delle preferenze (`askAI.…`, `llm.task.askAI`, `ollama.think.askAI`), il nome della finestra (`DreaMailMainWindow`) e il valore `askAI` della colonna `llmUsage.task` partono nuovi con il bundle nuovo; nessuna tabella né identificativo di migrazione porta il nome, quindi nessuna migrazione dello schema è stata toccata. Il pannello About perde "Support MishMail" e guadagna la riga "Based on MishMail by Ron Boger."; `.github/FUNDING.yml` e la sezione Support del README sono rimossi. Il nome vecchio resta solo dove è storia o attribuzione: voci passate del changelog, decisioni e step già registrati, archivi, studi, riferimenti all'upstream, la sezione del README per chi viene da MishMail. Il test `OldProductNameTests` vieta il ritorno del nome vecchio nell'albero del prodotto, con un elenco esplicito di eccezioni. Il prefisso `MM` delle funzioni Objective-C dell'app (`MMEnsureTextLayout`) non è il nome e resta. |
| DEC-070 | **Firme: seguono Gmail da sole** (affina DEC-055) | Le firme di Gmail (`users.settings.sendAs`, una per indirizzo: quella "per i nuovi messaggi"; le firme con nome e la predefinita per le risposte non sono in nessuna API ufficiale) si copiano da sole: all'avvio, all'aggiunta di un account e all'apertura di una finestra di composizione, al più ogni 5 minuti per account; "Importa da Gmail" è tolto. Una firma di Gmail vista per la prima volta diventa predefinita **solo per i nuovi messaggi** e solo se non ce n'è già una; la predefinita per risposte e inoltri si sceglie in Impostazioni (confermato dal proprietario). Una firma scritta in DreaMail non è mai sovrascritta né cancellata dall'importazione; una firma sparita da Gmail resta, segnata "No longer on Gmail". L'HTML della firma è trattato come non fidato: passa da un filtro a elenco di ciò che è ammesso (niente script, immagini, URL diversi da http/https/mailto, valori negativi, altezze; al più 10.000 caratteri e 64 livelli), è salvato già filtrato (migrazione v67) e rifiltrato in anteprima e all'invio. All'invio l'HTML della firma sostituisce il blocco in testo semplice solo nella parte scritta dall'utente e solo se la firma non è stata modificata; l'editor resta Markdown, quindi l'aspetto si vede in un'anteprima di sola lettura "Signature as sent". Accettato: due firme con testo identico e stile diverso usano lo stile della prima. Non verificato senza un Mac: il comportamento di libtidy sugli input ostili. |
| DEC-071 | **Etichette: menu come Gmail, colore di famiglia** (affina DEC-023) | Ogni etichetta utente ha il menu di Gmail web ("⋮" e clic destro): colore, visibilità nell'elenco etichette e nell'elenco messaggi (`messageListVisibility`, migrazione v66), modifica, rimozione, sottoetichetta. **Colore: l'ultima scelta è quella che si vede**: scegliere un colore di Gmail, o toglierlo, cancella il colore "solo su questo Mac" dell'etichetta e delle annidate; un colore (dei due tipi) dato a un genitore va a tutte le annidate, a ogni livello; una figlia colorata dopo tiene il suo colore finché non cambia di nuovo quello del genitore. **Una sottoetichetta nuova prende il colore del genitore** (Gmail non lo fa: richiesta del proprietario). La famiglia è per prefisso del nome (`nome/`). **Rinomina e spostamento** portano con sé le annidate; se una parte fallisce le rinomine riuscite sono annullate e i nomi riletti da Gmail; se anche l'annullamento fallisce, un avviso elenca chi ha il nome nuovo e chi il vecchio, con "Retry". **Rimozione**: toglie le annidate (dalla più profonda) e, in locale, tutto ciò che le riguarda (DEC-019), comprese le viste salvate che le mostrano, nominate nella conferma; una vista che la escludeva soltanto resta e perde quel filtro; le conversazioni restano. Le modifiche alle etichette non si mettono in coda: senza rete l'azione lo dice e non fa nulla. Non verificato: se `labels.patch` su un genitore rinomina già le figlie lato server (gestito come successo se la figlia ha già il nome nuovo). |
| DEC-072 | **Prima sincronizzazione progressiva** | La prima sincronizzazione (e l'allargamento di "Keep mail from") elenca prima l'Inbox e poi tutto il periodo, dal più recente; ogni blocco di messaggi è salvato insieme alle righe delle sue conversazioni nella stessa transazione, e l'elenco si ricarica al più una volta al secondo: la posta si vede e si usa mentre scarica. Le azioni fatte durante il passaggio sono tenute in memoria (solo id di conversazioni ed etichette) e riapplicate ai messaggi con data non successiva all'azione quando una pagina successiva ricostruisce la conversazione; un'azione rifiutata da Gmail è dimenticata. L'id di cronologia del primo tentativo è conservato finché la prima sincronizzazione non finisce; un tentativo ripreso rilegge prima la cronologia da quell'id. La posta arretrata non genera notifiche; quella nuova sì. L'accesso finisce quando token e riga dell'account sono salvati (passo non annullabile a metà); la prima sincronizzazione prosegue come lavoro tracciato, annullato e atteso a chiusura e rimozione; durante l'attesa del browser c'è "Cancel". Una rimozione è rifiutata mentre è in corso un accesso ed è marcata subito, così un accesso allo stesso indirizzo la vede. Nessuna modifica dello schema, nessun nuovo log. Accettato: un processo ucciso tra la scrittura nel Portachiavi e quella della riga lascia un token senza account (nessuna pulizia all'avvio); il confronto tra l'ora di Gmail e l'orologio del Mac non ha margine. Non verificato senza un Mac e un account vero: tempi, fluidità dell'elenco, flusso di Cancel col browser. |
| DEC-073 | **Barra laterale: categorie senza sotto-menu; i tasti sono della finestra aperta** (affina DEC-063) | Sotto "More" le viste di categoria (Promotions, Social) sono righe dirette subito sopra Spam; il gruppo "Categories" e il suo stato aperto/chiuso sono tolti (richiesta del proprietario: deviazione voluta da Gmail, che le raggruppa). Resta la regola di #76: con "Less" la vista aperta resta visibile. Mentre un foglio o un avviso della finestra principale è aperto (anche un popover aperto da un foglio), il monitor dei tasti lascia passare tutto: Esc chiude il foglio e nessuna scorciatoia agisce sulla finestra dietro; ogni foglio ha un'azione di annullamento. Conseguenza: con la conferma "Discard" della composizione aperta, Esc annulla la conferma. Non verificato senza un Mac: avvisi e conferme di sistema, popover, tasti durante l'animazione. |
| DEC-074 | **Firma ricca: mostrata una volta sola; incollabile da Gmail** (affina DEC-070) | In composizione una firma con l'aspetto di Gmail è mostrata **una sola volta**, come riquadro in sola lettura sotto il testo (niente copia in testo, niente anteprima "Signature as sent"); "Edit signature as text" la trasforma in testo, che parte com'è scritto. Lo stato è esplicito (`ComposeSignatureStyle`: legacy, plain, rich) e viaggia col messaggio: annulla invio, coda offline, invio programmato e Outbox (migrazione v68), bozze di Gmail (attributo `data-dreamail-signature` sul blocco della firma, letto e tolto solo nei tag della parte scritta dall'utente; ogni messaggio inviato da DreaMail ne è privo). In Settings una firma copiata da Gmail si incolla col suo aspetto (solo se sostituisce tutto il testo; fino a 300 KB, ridotta e poi filtrata con le stesse regole di DEC-070; immagini tolte) e resta una firma locale. "Keep a copy" scartato dal proprietario. Residui accettati: una bozza inviata direttamente da Gmail web o dal telefono può portare l'attributo (innocuo); con il testo citato espanso il riquadro sta sotto la citazione; l'RTF arriva quasi senza aspetto. Non verificato senza un Mac: se Gmail toglie lo spazio di "-- " (il confronto lo ignora). |
| DEC-075 | **Barra laterale: ordine scelto dall'utente; "More" chiuso nasconde tutto** (affina DEC-063, corregge DEC-073) | Le viste di sistema si riordinano col trascinamento, anche attraverso la riga "More" (sopra: sempre visibile; sotto: nascosta con "More" chiuso). L'ordine è **per account** (chiave `sidebar.system.order.<account>`, tolta con l'account, DEC-019); la vista "tutti gli account" ha il proprio. "Reset Sidebar Order" (menu View e clic destro) torna all'ordine di Gmail. Con "More" chiuso non è elencato nulla di ciò che sta sotto, **compresa la vista aperta** (richiesta del proprietario: annulla la regola di #76 mantenuta in DEC-073); lo stesso per il "More" delle etichette. Resta DEC-063: Reminders compare sopra "More" finché c'è un promemoria, anche se l'ordine salvato la tiene sotto. "More" è sempre elencata, anche vuota. Deviazione voluta da Gmail, che non permette di riordinare le viste di sistema. Non verificato senza un Mac: trascinamento reale e VoiceOver. |
| DEC-076 | **Densità: elenco e barra laterale, due scelte separate** | Settings → Appearance: "List density" e "Sidebar density", Comfortable (predefinita, invariata) o Compact, come la densità di Gmail. Compact riduce solo lo spazio verticale: riga dell'elenco con 2 pt invece di 6 sopra e sotto, riga della barra laterale alta almeno 22 pt invece di 30. Caratteri, icone e intestazioni di sezione ("Today", "Yesterday") non cambiano (richiesta del proprietario). La densità della barra laterale è stata chiesta dal proprietario nella sessione di lavoro. |
| DEC-077 | **Selezione: il colore accent vuol dire "aperto", non "ha il fuoco"** | Come in Gmail, la conversazione aperta e la vista corrente della barra laterale restano nel colore accent (personalizzato, o quello di selezione del sistema) anche quando il fuoco è altrove o la finestra è inattiva; testo e icone con lo stesso inchiostro in ogni stato. Poiché due liste possono mostrare insieme una riga colorata, quella con il fuoco della tastiera ha una barretta di 3 pt sul bordo iniziale. Vale su macOS 26 (stesso meccanismo della selezione dipinta dall'app); su macOS 14–15 resta il grigio di sistema. Assunzione dichiarata e non contestata: vale anche a finestra inattiva. Il "+" e il "⋮" delle etichette sono neutri (mai accent), il "⋮" è verticale come in Gmail. |
| DEC-078 | **Etichette sotto "More" senza doppioni (parte sostituita da DEC-080); snooze: nomi inglesi sempre, titoli in inglese** (affina DEC-063) | Nessuna etichetta è elencata due volte: una sottoetichetta nascosta di un'etichetta visibile compare sotto "More" come riga propria col nome completo ("madre/figlia"), senza ripetere la madre; le etichette nascoste sotto una madre nascosta restano annidate (richiesta del proprietario: la madre ripetuta sembrava un errore). Snooze: l'interfaccia è in inglese, quindi i nomi inglesi di giorni e mesi sono sempre accettati, qualunque sia la lingua del Mac; quelli della lingua del Mac restano accettati (anche senza accenti); i suggerimenti sono sempre intitolati in inglese. Le parole chiave in altre lingue ("domani") restano fuori. Con calendari non gregoriani valgono solo i nomi locali dei mesi. |
| DEC-079 | **Barra laterale: intera o striscia di icone, mai del tutto nascosta** | Come la navigazione ridotta di Gmail: "nascondere" la barra laterale la riduce a una striscia di sole icone (Search, viste di sistema nell'ordine dell'utente fino a "More"; niente etichette né viste salvate) larga 40 pt, a destra della barra degli account; la fascia in alto diventa 104 pt (64 + 40) così i bordi coincidono (richiesta del proprietario: usare il dislivello che si vedeva a barra nascosta). Due soli stati, stesso comando e stessa chiave di prima. Scelte: nessun numero nella striscia (conteggio nel suggerimento e per VoiceOver); Search attiva il campo di ricerca della barra in alto, senza riaprire la barra laterale (dalla PR #113, che ha spostato il campo accanto al nome della vista; prima riapriva la barra intera); "More" segue DEC-075; niente espansione al passaggio del mouse (deviazione voluta da Gmail) e niente riordino nella striscia; la striscia non conta nella soglia dei tre pannelli; finestra stretta, conversazione a tutta finestra e composizione affiancata restano come prima (fascia 90 pt, niente striscia); la densità della barra laterale non si applica alla striscia. Lo stato in memoria di un account rimosso è dimenticato (DEC-019). |
| DEC-080 | **Etichette: famiglie intere e ordine di Gmail** (sostituisce la parte "etichette" di DEC-078; affina DEC-063) | Confronto diretto del proprietario con Gmail web: una famiglia non è mai divisa. Un'etichetta di primo livello e tutto il suo sottoalbero stanno insieme, annidati, sopra o sotto il "More" delle etichette secondo la visibilità in Gmail dell'etichetta di primo livello ("hide" sotto; "show" sopra; "show if unread" sopra quando c'è posta non letta in qualunque etichetta della famiglia: assunzione, non verificata su Gmail). La visibilità di una sottoetichetta non cambia dove compare. Nessuna riga col percorso "madre/figlia" (la regola di DEC-078, proposta dall'orchestratore, era sbagliata), nessun nome due volte. Ordine predefinito: quello di Gmail (confronto senza distinzione di maiuscole e accenti, numeri per valore, simboli ed emoji per primi, lingua fissa "en" così è uguale su ogni Mac). Un riordino fatto a mano in Organize Labels vince, e vale solo per il gruppo di sorelle della riga trascinata; gli altri gruppi seguono Gmail. La migrazione v70 azzera una volta l'ordine salvato di tutte le etichette (la v69, che azzerava solo gli ordini identici a quello per codice dei caratteri, non bastava: un solo vecchio trascinamento faceva sembrare voluto tutto l'elenco); "Use Gmail's Order" in Organize Labels torna all'ordine di Gmail in ogni momento. Un'etichetta senza colore è disegnata col solo contorno. Un'etichetta cancellata su Gmail perde anche le preferenze locali (DEC-019). Punto aperto: visibilità di una sottoetichetta diversa tra Gmail e DreaMail, causa non trovata. |
| DEC-081 | **Cestino: vale il messaggio, non la conversazione** (affina DEC-019) | Come in Gmail: una conversazione è "nel Cestino" solo quando tutti i suoi messaggi lo sono. Un messaggio nuovo in una conversazione cestinata la riporta in Inbox. "Cancellato vuol dire sparito" vale per il singolo messaggio: in una conversazione viva i messaggi cestinati non sono mostrati, contati, cercati, citati nelle risposte né passati a MCP/IA, e non generano notifiche. La regola precedente (un solo messaggio cestinato nascondeva tutta la conversazione, da #75) faceva perdere posta nuova: difetto segnalato dal proprietario. Riparazione una tantum per account delle righe salvate, solo dove la vecchia regola aveva agito, mai su una cancellazione locale non ancora confermata o in coda. Un fallimento della sincronizzazione è mostrato ("Sync failed · last synced …"), con testo generico. Completato con #106: il Cestino (e `in:trash`) elenca anche le conversazioni cestinate in parte, con riga e lettura dei soli messaggi cancellati; da lì "Move to" ripristina solo quei messaggi e gli altri comandi sono disattivati (non si agisce mai su messaggi vivi che non si vedono); l'annulla di "Cestina" ripristina la conversazione e ri-cestina solo ciò che era già cancellato prima, così nessun messaggio sconosciuto in locale resta nel Cestino di Gmail e nessuna cancellazione precedente ritorna; un ripristino rifiutato da Gmail è annullato anche in locale, con errore visibile. Nessuna chiamata di cancellazione definitiva. |
| DEC-082 | **Selezione della barra laterale: squadrata, senza trattino del fuoco** (corregge DEC-077) | Decisione del proprietario dopo aver visto l'app: la riga selezionata della barra laterale è una banda rettangolare come quella dell'elenco dei messaggi, non una capsula arrotondata (la capsula rientrata di #99, scelta dall'orchestratore, è ritirata), dipinta dall'app in ogni stato così la capsula di sistema non si vede mai; vale anche per Settings e per la striscia di icone. Il trattino verticale del fuoco introdotto con DEC-077 è tolto ovunque. La banda arriva a filo dell'elenco sul lato destro; la barra laterale non mostra la barra di scorrimento. Sul lato sinistro restano 8 pt: è il margine che macOS 26 dà alla colonna della barra laterale, non chiuso per non forzare il comportamento di sistema. Resta di DEC-077: il colore accent vuol dire "aperto" e resta senza fuoco. |
| DEC-083 | **Pallino dell'etichetta nella barra laterale: nel tema scuro sempre un riempimento visibile** (precisa DEC-029) | Nel tema scuro un colore troppo vicino allo sfondo della barra laterale (grigio scuro, nero) non riceve più il contorno di DEC-029, che su un riempimento quasi invisibile si leggeva come "senza colore": il riempimento è schiarito solo quanto basta (differenza 25 dallo sfondo della barra). Nel tema chiaro resta DEC-029: colore vero di Gmail e contorno sottile dove serve. Solo l'etichetta senza colore è un contorno. Il foglio "Label color" mostra il colore in archivio ("Current:"). PR #108. |
| DEC-084 | **Inbox mostra tutta la posta con l'etichetta Inbox** | Come un Gmail senza schede per categoria: nessuna categoria (Promotions, Social, Updates, Forums) è nascosta da Inbox per impostazione predefinita, né su un'installazione nuova né su una esistente; conteggi, badge e notifiche seguono l'elenco. L'API di Gmail non dice se l'utente usa le schede, quindi non le si imita. Un filtro di categoria è una scelta esplicita dell'utente; dove un valore salvato non si distingue dal vecchio default, si mostra la posta. Le viste salvate restano com'erano (scelta del proprietario). Decisione dopo la segnalazione di posta nuova mancante in Inbox; PR #111. |
| DEC-085 | **Inbox unificata disattivabile** | Richiesta del proprietario: un'impostazione globale (Settings → Appearance, attiva per impostazione predefinita) toglie la vista "All accounts" e ogni via per raggiungerla; l'app mostra allora il primo account. Gmail non ha una posta unificata: è una regola propria dell'app. Le viste salvate di tutti gli account restano nascoste finché l'opzione è spenta, senza essere modificate né cancellate (scelta del proprietario); badge, numero sul Dock e notifiche non dipendono dall'opzione. PR #114. |
| DEC-086 | **Messaggi cancellati visibili a richiesta nella conversazione viva** | Come Gmail web: una conversazione con messaggi nel Cestino e altri no mostra la riga "N deleted messages in this conversation" con "View"; solo dopo il clic i messaggi cancellati compaiono sul posto, segnati "In Trash", con "Restore" e "Restore all". Precisa DEC-019 e DEC-081: "cancellato vuol dire sparito" resta vero per riga dell'elenco, ricerca, conteggi, citazioni, riassunto e MCP; la riga dice solo quanti sono. Più severo di Gmail: un messaggio cancellato aperto non carica immagini remote senza un clic e non avvia il controllo OpenPGP. PR #107. |
| DEC-087 | **Etichette disegnate con il preset di colore di Gmail** | Gmail può dare a un'etichetta un "preset" di colore (`colorPreset`, 21 valori) che REST v1 non documenta: l'app lo legge se arriva, lo conserva così com'è e lo mostra nel foglio del colore. Il preset decide il disegno solo quando il colore di Gmail manca o è la coppia neutra `#eeeeee`/`#222222`; un colore vero di Gmail e un colore scelto solo su questo Mac vengono prima. L'app non scrive mai il preset: per toglierlo serve Gmail web, e una rimozione che lo lascia è un errore dichiarato, non un successo. Una nuova sottoetichetta eredita il colore con cui la madre è disegnata (precisa DEC-071), mai quello scelto solo su questo Mac. Il nome del preset è mostrato solo se ben formato, altrimenti "unknown preset". Prosegue DEC-083. PR #118. |
| DEC-088 | **"Move to inbox" e menu del clic destro come Gmail** | Come Gmail web: una conversazione che non è in Inbox mostra "Move to inbox" dove quelle in Inbox mostrano "Archive" (non nel Cestino, non nello Spam, non una bozza sola: lì restano le azioni proprie). Il pulsante conserva le etichette; "Move to… → Inbox" da dentro un'etichetta la toglie, e da una conversazione cestinata toglie anche TRASH. Scelta dell'app, non verificata su Gmail: riportare in Inbox toglie anche il silenziamento. Nessun tasto predefinito (Gmail non ne ha). Il menu del clic destro sulla riga segue ordine, gruppi, parole e icone di Gmail, con le voci proprie dell'app in coda; "Delete" è la parola di Gmail solo in questo menu, altrove resta "Trash" finché il proprietario non decide. Il clic destro su una di più righe spuntate agisce sull'insieme spuntato. Fuori per scelta: "Add to Tasks" (deciso dal proprietario), "Forward as attachment" e "Open in new window" (mancano i mattoni nell'app). Un'azione ha una sola icona in tutta l'app. PR #116. |
| DEC-089 | **Promotions e Social disattivabili per account** | Ogni account ha "Show Promotions and Social" (acceso per default): spento, l'account non ha le due righe, le due scelte nei filtri né il chip di categoria. È una scelta di presentazione, non un filtro: la posta resta in Inbox, All Mail, ricerca, conteggi, Dock e notifiche (DEC-084 resta valida). In "All accounts" le due righe si vedono se almeno un account le ha accese ed elencano solo la posta di quegli account. Un filtro di categoria memorizzato per Inbox è senza effetto per un account spento, nel suo ambito come in "All accounts", e resta memorizzato. Le viste salvate conservano i propri filtri anche per un account spento (deciso dal proprietario). Scostamento da Gmail, che ha le schede per casella e non questo interruttore nell'app. PR #119. |
| DEC-090 | **Azioni sul singolo messaggio e apertura sui messaggi stellati** | Come Gmail web: ogni messaggio aperto ha stella, Reply, Reply all e un menu "⋮" con le sole voci che l'app sa fare, senza voci spente. La stella e "Delete this message" valgono per quel solo messaggio; cancellare un messaggio sposta nel Cestino solo quello (etichetta TRASH, mai una cancellazione definitiva) e la conversazione resta dov'è finché ha un messaggio vivo (DEC-081); cancellato l'ultimo, va nel Cestino la conversazione. Deciso dal proprietario: una conversazione con messaggi stellati si apre sul messaggio stellato più recente; precisazione dell'orchestratore: restano aperti anche l'ultimo messaggio e i non letti (al più 5), e se c'è posta non letta più recente della stella la vista va sul più vecchio di quei non letti. Senza stelle l'apertura non cambia. Da un messaggio cestinato non si offrono azioni che toccano i messaggi vivi (Delete, Report spam, Block). Fuori: Print (in attesa del permesso di stampa), Add sender to Contacts, Report phishing, Translate. PR #110. |
| DEC-091 | **Barra di selezione come Gmail ed etichette su più conversazioni** | Come la barra di Gmail web: con più conversazioni spuntate la barra offre Archive o Move to inbox, Report spam o Not spam, Trash, Read/Unread, Snooze, Move to…, Label as… e Star, e ciò che non entra passa sotto "⋮". Scelte dell'app: dove Gmail nasconde un pulsante (Cestino, Spam) qui è spento; una selezione mista di spam mostra Report spam; Star è l'ultima. "Label as…" su più conversazioni segue Gmail: spunta se l'hanno tutte, trattino se alcune, un clic la aggiunge a tutte oppure la toglie quando l'avevano tutte; si scrivono e si inviano solo le conversazioni che cambiano, e l'annullamento rimette esattamente quelle. Le etichette sono di un account: le conversazioni di altri account restano fuori, con un avviso; le copie cestinate di conversazioni vive non sono contate né toccate (DEC-081). PR #123. |
| DEC-092 | **Colore delle etichette solo di Gmail** (sostituisce in parte DEC-071 e DEC-087) | Il foglio "Label color" è come il menu di Gmail web: la griglia dei colori di Gmail e "Remove color", nient'altro. Il colore "solo su questo Mac" non c'è più: non è letto né scritto, un'etichetta che lo aveva mostra di nuovo il colore di Gmail; il valore resta nel database (colonna `color`), senza migrazione. Tolta anche la riga diagnostica "Current:" (#118), non più necessaria: i colori mancanti erano colori non standard in Gmail, corretti dal proprietario. Restano valide da DEC-071 la propagazione del colore alle annidate e l'eredità della sottoetichetta nuova (DEC-087), solo per il colore di Gmail. PR #127. |
| DEC-093 | **Menu "⋮" del messaggio come Gmail, con la stampa** (precisa DEC-090) | Il menu "⋮" di un messaggio aperto ha i gruppi di Gmail web separati da linee: Reply, Reply all, Forward / Delete, Mark as unread / Block (o Unblock), Report spam (o Not spam) / Filter messages like this, Print, Download message, Show original. Titoli di Gmail ("Reply all", "Delete", "Mark as unread", che segna da questo messaggio in poi); comportamento invariato. Fuori le voci che l'app non sa fare (Report phishing, Report illegal content, Translate). **Print** stampa il solo messaggio (intestazione con oggetto, mittente, destinatari, data; corpo come nel pannello) con il pannello di stampa di macOS; le immagini remote seguono la stessa scelta del pannello, JavaScript spento, un solo caricamento accettato; il nome del lavoro è l'oggetto (come Gmail). Permesso di sandbox `com.apple.security.print`. PR #129. |

## 3. Stack (verificato nel fork al commit `18294fa`, salvo dove indicato)

| Ambito | Scelta | Stato |
|---|---|---|
| Linguaggio | Swift 5.10; target macOS 14.0; Xcode 15.3+ | Verificato in `project.yml` |
| Progetto Xcode | Generato con `xcodegen` da `project.yml`; build tramite `Makefile` | Verificato |
| Interfaccia | SwiftUI del fork MishMail, con AppKit dove necessario | Indirizzo confermato; dettagli da validare |
| API e-mail | Gmail REST API | Confermato |
| Calendario | Google Calendar API (assente nel fork) + parser ICS (già presente) | Proposto |
| Autenticazione | OAuth 2.0 Authorization Code + PKCE S256, client Google di tipo "Desktop app" portato dall'utente | Verificato in `Auth/OAuth.swift` |
| Login macOS | Browser di sistema + listener loopback su `127.0.0.1`. La proposta `ASWebAuthenticationSession` della v0.6 è ritirata: sostituirebbe un flusso funzionante senza beneficio dimostrato (regola della sezione 8.2). | Verificato |
| Segreti | macOS Keychain per refresh token e client secret | Verificato; ACL da provare su macOS |
| Persistenza | SQLite/FTS5 tramite GRDB 3.0.0 del fork DuckDuckGo (`duckduckgo/GRDB.swift`) con SQLCipher | Verificato in `project.yml`; cifratura effettiva da provare su macOS |
| Contenuti HTML | `WKWebView` con protezioni per contenuti remoti (già presenti, sezione 12.4) | Verificato in sorgente |
| PGP | Libreria OpenPGP consolidata; integrazione da valutare | Da valutare |
| Distribuzione | Build locale Xcode; firma/notarizzazione solo se distribuita a terzi | Confermato per la fase iniziale |

## 4. Requisiti funzionali

La colonna "Stato nel fork" riporta ciò che il codice contiene al commit `18294fa`. È una lettura del sorgente, non una prova d'uso: ogni voce "presente" va confermata con l'app in esecuzione.

| Funzionalità | Approccio previsto | Stato nel fork | Stato requisito |
|---|---|---|---|
| Lettura, scrittura e ricerca | Gmail API | Presente | Richiesto |
| Scorciatoie in stile Gmail | Command system configurabile nell'app | Presente: tasti singoli riconfigurabili (`Support/KeyBindings.swift`) e command palette; copertura rispetto a Gmail da verificare | Richiesto |
| Label multiple e colori | Gmail API; label native di Gmail | Parziale: label e colori sincronizzati (`Gmail/SyncEngine.swift`), creazione label presente; modifica dei colori da verificare | Richiesto |
| Conversazioni/thread | ID thread Gmail | Presente | Implicito nell'esperienza Gmail |
| Eventi calendario | Google Calendar API | Assente | Richiesto |
| Inviti `.ics` e risposte RSVP | Parsing iCalendar e gestione delle risposte | Presente: parser, RSVP accetta/rifiuta/forse, `METHOD:REPLY`, istanze ricorrenti (`Support/CalendarInvite.swift`, `Support/ICSTimeZone.swift`) | Richiesto |
| PGP | Firma, verifica, cifratura, decifratura | Assente | Richiesto |
| Undo send | Invio differito locale con finestra di annullamento | Presente (`App/MailStore+Compose.swift`); comportamento ad arresto/riavvio dell'app durante la finestra da verificare | Richiesto |
| Snooze | Funzione personalizzata: Gmail API non espone uno snooze nativo generale | Presente ma solo locale (colonna `snoozeUntil`): non allineato allo snooze di Gmail Web e mobile | Richiesto; progettazione aperta |
| Unsubscribe | Intestazioni `List-Unsubscribe` e `List-Unsubscribe-Post` | Presente, incluso one-click RFC 8058 (`Support/ListUnsubscribe.swift`) | Richiesto |
| Filtri automatici | Filtri Gmail server-side quando disponibili | Parziale: sola lettura (`GET /settings/filters`); creazione e modifica mancanti | Richiesto |
| Funzionamento offline | Cache SQLite e sincronizzazione incrementale | Presente: cache cifrata, FTS5, coda delle operazioni offline | Proposto |
| Più account | — | Presente: inbox unificata multi-account | Da decidere se mantenerlo (sezione 7) |

## 5. Autenticazione e sviluppo locale

- Il client mostra il consueto flusso «Accedi con Google» nel browser di sistema; il redirect torna a un listener locale su `127.0.0.1`.
- L'app richiede accesso offline e conserva il refresh token nel Keychain; i token di accesso vengono rinnovati automaticamente.
- È preferibile riutilizzare lo stesso OAuth Client ID durante lo sviluppo, evitando revoche o rigenerazioni inutili dei token.
- Per gli scope Gmail, un progetto OAuth esterno in Testing produce refresh token con scadenza a 7 giorni. È stata proposta la modalità In production per l'uso personale, da verificare rispetto alle policy Google applicabili e agli avvisi di app non verificata.
- Gli scope richiesti oggi sono `gmail.modify`, `gmail.settings.basic`, `userinfo.email` e `userinfo.profile`. L'integrazione Calendar aggiungerà uno scope e richiederà un nuovo consenso per ogni account già collegato.
- La configurazione OAuth di Google è distinta dalla pubblicazione sul Mac App Store.
- I token possono comunque essere invalidati per revoca, inattività, modifiche alle credenziali o controlli di sicurezza: non è garantito un accesso perpetuo.

## 6. Vincoli tecnici e rischi

1. Snooze: assenza di una API pubblica generale per lo snooze nativo Gmail. Lo snooze del fork è locale, quindi un thread posticipato nell'app non risulta posticipato in Gmail Web o mobile e viceversa: è una divergenza dall'obiettivo di fedeltà della sezione 1. Definire semantica, notifiche e comportamento con app chiusa.
2. Undo send: l'e-mail non viene richiamata dopo l'invio; bisogna ritardare l'invio effettivo e gestire arresti/riavvii dell'app.
3. Sincronizzazione: utilizzare history.list e prevedere la ricostruzione quando l'ID di cronologia non è più valido (il fork gestisce già il caso `historyExpired`). Per un client solo desktop, valutare polling; le notifiche push Gmail richiedono Google Cloud Pub/Sub.
4. OAuth Gmail: `gmail.modify` è uno scope restricted, con limitazioni e requisiti di verifica (assessment CASA) in caso di distribuzione più ampia. Il modello "ognuno porta il proprio client OAuth" del fork evita la verifica finché l'app non viene distribuita con un client condiviso.
5. PGP: gestione delle chiavi, interoperabilità MIME e sicurezza del rendering richiedono progettazione specifica. Vanno inoltre definiti i flussi esistenti che toccano il testo in chiaro: bozze sincronizzate su Gmail, indice FTS locale e funzioni AI.
6. Calendario: distinguere inserimento evento, modifica/cancellazione e risposta RSVP all'organizzatore. Con la Calendar API evitare la doppia risposta (e-mail `METHOD:REPLY` più aggiornamento via API).
7. HTML e-mail: isolare contenuti attivi e controllare caricamento di risorse remote.
8. Identità del fork: bundle ID (`dev.ronboger.MishMail`) e canale di aggiornamento (`ronboger/mishmail`) sono ancora quelli dell'upstream. Finché non cambiano, il fork collide con un'eventuale installazione upstream e l'updater proporrebbe le release upstream, sostituendo il fork.
9. Divergenza dall'upstream: l'upstream è attivo (v0.7.0 del 13 novembre 2026) e le remediation toccano file grandi (`MailStore.swift`, `SettingsView.swift`, `UpdateChecker.swift`); ogni PR locale aumenta il costo dei futuri allineamenti.

## 7. Questioni aperte

- Verificare compilazione ed esecuzione dei test di MishMail su macOS; verificare compilazione, architettura, test, licenza e dipendenze di Postie. La licenza MIT di MishMail è confermata nel file `LICENSE`.
- Definire il set minimo di funzionalità della prima versione (MVP).
- Stabilire se mantenere il supporto multi-account già presente nel fork.
- ~~Stabilire se mantenere le funzioni AI e il server MCP del fork.~~ Deciso: spenti per il momento (DEC-011). Sono estranee all'obiettivo della sezione 1 e concentrano quattro finding su dodici (F-05, F-06, F-12 e parte di F-04); disattivarle ridurrebbe la remediation.
- **Definire il rapporto con l'upstream:** proporre a monte le correzioni di sicurezza o mantenerle solo nel fork; segnalare in modo riservato F-01, che riguarda anche gli utenti upstream, secondo `SECURITY.md`.
- Definire lo snooze: con app chiusa, su dispositivi diversi e rispetto allo snooze di Gmail Web e mobile.
- Selezionare la libreria OpenPGP e il modello di gestione chiavi; decidere il trattamento di bozze, ricerca e AI per i messaggi cifrati.
- Definire integrazione Google Calendar (scope, nuovo consenso, doppia risposta RSVP) e notifiche.
- Validare la configurazione Google Cloud OAuth per uso personale duraturo.
- Stabilire se in futuro distribuire l'app ad altri utenti.

## 8. Strategia di sviluppo: MishMail + Postie

Repository di sviluppo (fork): bateman/dreamail (fino a DEC-065 bateman/mishmail; GitHub reindirizza il vecchio indirizzo)
Repository upstream (originale): ronboger/mishmail
Repository di riferimento Postie: igorkulman/Postie

Il repository bateman/mishmail è il riferimento per il lavoro sul progetto; mantenere l'upstream distinto per seguire le modifiche originali ed eventualmente integrarle. Al 23 novembre 2026 il `main` del fork coincide con il commit auditato `18294fa`.

Decisione di indirizzo (DEC-007). Partire da un fork di MishMail come applicazione principale, mantenendone — previa verifica — l'interfaccia SwiftUI, il modello locale e l'integrazione Gmail API. Studiare Postie come sorgente selettiva di componenti: non fondere automaticamente i due repository. MishMail è Swift/SwiftUI con licenza MIT (verificato); per Postie la stessa dichiarazione resta da confermare nei file LICENSE e nelle dipendenze prima di copiare codice.

### 8.1 Responsabilità dei progetti

| Progetto | Ruolo previsto | Nota |
|---|---|---|
| **MishMail — [fork bateman/mishmail](https://github.com/bateman/mishmail)** | Base del fork: app, UI, account, modello dati, sincronizzazione, funzionalità di produttività | Conservare ciò che supera l'audit; non assumere robustezza dal solo README. |
| **Postie** | Repository di riferimento: confronto di test e casi limite ICS/RSVP, possibili componenti di composer/sync | Riutilizzare solo ciò che supera confronto, test e analisi delle dipendenze. Non è più la fonte primaria di ICS/RSVP. |
| **Codice nuovo nel fork** | Funzionalità mancanti, integrazioni e adattatori | Preferire moduli isolati, testabili e privi di duplicazioni. |

### 8.2 Componenti da valutare per il trasferimento

| Priorità | Componente | Approccio |
|---|---|---|
| **P0** | **OAuth, token e Gmail API** | Confrontare sicurezza, retry, paginazione e gestione errori dei due progetti; **non** sostituire il client OAuth funzionante senza evidenze di beneficio. |
| **P1** | **Inviti ICS e RSVP** | Già implementati in MishMail. Fare una gap analysis rispetto a Postie (casi limite del parser, fusi orari, aggiornamenti e cancellazioni, test) e portare solo ciò che manca. Declassato da P0 nella v0.7. |
| **P1** | **Composer, bozze e allegati** | Valutare componenti specifici e importare soltanto quelli migliori rispetto alla base. |
| **P1** | **Sync incrementale e recupero** | Confrontare `historyId`, ricostruzione dopo invalidazione, quota/rate limit, offline e operazioni pendenti. Preferire miglioramenti chirurgici. |
| **P1** | **Test, fixture e demo** | Adattare test automatici indipendenti da account reali; mantenere tracciabilità del codice di provenienza. |

Funzionalità assenti nel fork, da implementare: calendario Google completo, OpenPGP, creazione e modifica dei filtri Gmail server-side.

Funzionalità presenti nel fork, da verificare in uso e completare dove serve: colori e gestione delle label, unsubscribe RFC 8058, sicurezza HTML, shortcut configurabili, snooze, undo send. La v0.6 le elencava come non coperte.

### 8.3 Regole per integrare codice tra i due progetti

1. Audit prima del fork operativo: clonare, compilare ed eseguire test e modalità demo di entrambi; controllare stato manutenzione, licenze di progetto e dipendenze, vulnerabilità e struttura del codice.
2. Mappare le dipendenze: per ogni funzionalità candidata individuare file/classi, modelli, networking, OAuth, persistenza e test collegati.
3. Separare logica e interfaccia: estrarre la parte riutilizzabile in un servizio/modulo Swift autonomo; evitare di introdurre due database, due client Gmail o due gestori OAuth.
4. Adattare, non incollare: interfacciare il modulo con modelli e servizi già esistenti in MishMail, documentando modifiche e provenienza.
5. Test prima del merge: test unitari, integrazione Gmail con fixture/mocks, verifica regressioni di sync e UI; poi test limitati su account reale dedicato.
6. Conformità licenze: conservare copyright e avvisi MIT applicabili, verificare anche le licenze di ogni componente e dipendenza trasferiti. Registrare file e commit sorgente nel PR.
7. Mantenibilità: preferire cherry-pick/adattamento tracciato o moduli isolati al copia-incolla indiscriminato; confrontare periodicamente i cambi upstream senza prevedere merge automatici. La regola vale anche per l'upstream MishMail, non solo per Postie.

### 8.4 Roadmap operativa

☐ Milestone 0 — Validazione della base e sicurezza: audit statico completato sul commit `18294fa`. Ordine: (a) build pulita in Xcode, test nativi e demo; (b) decisione GO / NO-GO su MishMail come base; (c) solo in caso di GO, remediation P0/P1. La v0.6 metteva la decisione dopo le remediation.
☐ Milestone 1 — Fork stabile: identità propria (bundle ID, nome app, canale di aggiornamento, plist launchd in `scripts/`), attribuzioni/licenze, build riproducibile, updater disabilitato (DEC-009), OAuth Client ID personale e persistenza sessione, smoke test Gmail/SQLite/shortcuts.
☐ Milestone 2 — ICS/RSVP: verifica su inviti reali dell'implementazione esistente; gap analysis rispetto a Postie e porting selettivo solo di ciò che manca.
☐ Milestone 3 — Parità Gmail: completamento di label e colori, creazione e modifica dei filtri lato server, verifica di shortcuts, undo send e unsubscribe già presenti, riprogettazione dello snooze; validazione con Gmail Web.
☐ Milestone 4 — Calendario e PGP: Google Calendar API (nuovo scope), modifiche/cancellazioni eventi, firma/verifica e cifratura/decifratura OpenPGP; revisione sicurezza.
☐ Milestone 5 — Qualità desktop: accessibilità macOS, performance con caselle grandi, offline, packaging e aggiornamenti.

Criteri per cambiare base e passare a Postie: MishMail non compila in modo riproducibile, presenta problemi di sicurezza/architettura costosi da correggere, o la migrazione richiesta supera il costo di implementare in Postie le funzionalità mancanti. In tal caso documentare un nuovo ADR: la scelta attuale non è irreversibile.

## 9. Progetti di riferimento — shortlist prioritaria

Obiettivo della ricognizione: studiare soluzioni esistenti prima di progettare o implementare da zero autenticazione, sincronizzazione, modello locale e interazioni. La shortlist include cinque progetti open source e un benchmark proprietario. MishMail è ora il candidato principale per il fork; Postie il primo riferimento di confronto (sezione 8). Gli altri restano riferimenti di confronto.

| Priorità | Progetto | Tipo / tecnologie dichiarate | Cosa analizzare | Link |
|---|---|---|---|---|
| P0 | **Postie — riferimento selettivo** | Open source; SwiftUI, Gmail API, SQLite | Architettura macOS nativa; OAuth; sincronizzazione; cache; test e demo | [GitHub](https://github.com/igorkulman/Postie) |
| P0 | **MacMail** | Open source; SwiftUI/AppKit, Gmail API, Google Calendar, SQLite | Integrazione Gmail + Calendar; composer; undo send; allegati; multiaccount | [GitHub](https://github.com/d-sanoj/MacMail) |
| P0 | **MishMail — base del fork** | Open source; SwiftUI, Gmail API, SQLite | Local-first; modello dati; navigazione da tastiera; demo senza account | [Fork](https://github.com/bateman/mishmail) · [Upstream](https://github.com/ronboger/mishmail) |
| P1 | **Exo** | Open source; Rust/egui, Gmail e Calendar API | Workflow stile Superhuman; split inbox; snooze; send later; shortcuts | [GitHub](https://github.com/m1guelpf/Exo) |
| P1 | **Thunderbird** | Open source; desktop multipiattaforma | OpenPGP; MIME; HTML; inviti ICS/RSVP; robustezza e test | [GitHub](https://github.com/thunderbird/thunderbird-desktop) |
| UX | **Mimestream** | **Proprietario**; client macOS per Gmail | Benchmark per label/colori, thread, ricerca, filtri, UX macOS e integrazione Gmail | [Sito](https://mimestream.com/) |

Ordine operativo: verificare prima MishMail e Postie e applicare la roadmap della sezione 8; consultare MacMail per Calendar/composer, Exo per interazioni, Thunderbird per PGP/MIME e Mimestream per benchmark UX.

Checklist di analisi (da compilare per ciascun progetto):

☐ Verificare che repository, licenza e attività di manutenzione siano effettivamente disponibili e aggiornati.
☐ Mappare architettura, dipendenze e versione degli strumenti di build.
☐ Esaminare OAuth/PKCE, Keychain e rinnovo dei token.
☐ Esaminare Gmail API: paginazione, historyId, recovery, rate limiting, sincronizzazione offline.
☐ Esaminare schema SQLite, FTS, thread, label e gestione delle operazioni pendenti.
☐ Esaminare UI nativa, shortcut, accessibilità, performance e test.
☐ Valutare sicurezza: rendering HTML, contenuti remoti, allegati, PGP e dati locali.
☐ Registrare cosa riutilizzare, cosa riprogettare e i rischi di licenza.

## 10. Altri progetti — backlog per analisi futura

Questa lista conserva tutti gli altri nomi emersi nella ricognizione, separati dalla shortlist. I dettagli funzionali sono piste di analisi, non funzionalità verificate eseguendo le app. Verificare sempre repository, licenza, disponibilità del codice e stato di manutenzione prima di pianificare riuso.

### 10.1 Gmail-centrici e client desktop sperimentali

| Progetto | Link | Motivo di interesse |
|---|---|---|
| **7orb** | [Sito](https://7orb.com/) | Swift 6/SwiftUI, OAuth, GRDB, `historyId`, label e cache offline; distinguere roadmap da codice effettivo e verificare il repository. |
| **MailRovers** | [GitHub](https://github.com/wilbertliu/mailrovers) | Local-first, sincronizzazione Gmail, recupero delle operazioni, FTS5. |
| **Mach** | [GitHub](https://github.com/bborn/mach) | Rust/Tauri/React; Gmail + Calendar; comandi e scorciatoie. |
| **Velo** | [GitHub](https://github.com/hscale/velo-email-client) | Label, drag & drop, snooze, unsubscribe, filtri, command palette. |
| **Meru** | [GitHub](https://github.com/zoidsh/meru) · [Sito](https://meru.so/) | Wrapper/integrazione desktop di Gmail; notifiche, multiaccount e personalizzazioni; meno pertinente come base SwiftUI. |
| **Morrow Mail** | [GitHub](https://github.com/Coke1120/Morrow-Mail) | Gmail API, calendario, multiaccount, workflow avanzati. |
| **EmailOps** | [GitHub](https://github.com/emailops/emailops) | Undo send, scheduled send, snooze, unsubscribe, notifiche, calendario. |
| **Godwit** | [GitHub](https://github.com/godwit-email/godwit) | Estensibilità e architettura a plugin. |

### 10.2 Client macOS nativi e progetti Apple

| Progetto | Link | Motivo di interesse |
|---|---|---|
| **MMail** | [GitHub](https://github.com/moerdowo/MMail) | SwiftUI/IMAP; shortcut; rendering HTML e protezioni privacy. |
| **Letterbox** | [GitHub](https://github.com/Mr-vero/letterbox) | SwiftUI; classificazioni Needs Reply, To Do, Waiting. |
| **Minimail** | [GitHub](https://github.com/paperfoot/minimail-mac) | SwiftUI; menu bar, notifiche interattive, snooze, undo send. |
| **Brev** | [Sito](https://brevmail.eu/) | Client nativo Apple; Gmail API/IMAP dichiarati, sorgente e licenza da verificare. |
| **Mailflare** | [Sito macOS](https://mailflare.co/macos) | SwiftUI + core Rust dichiarati; coda offline e separazione dei componenti. |

### 10.3 Sicurezza, protocolli e progetti multipiattaforma

| Progetto | Link | Motivo di interesse |
|---|---|---|
| **Penguin Mail** | [GitHub](https://github.com/c9dev/penguin-mail) | GTK/Rust; OpenPGP, S/MIME, contatti, calendario e regole. |
| **Pelton** | [Sito](https://pelton.app/) | OpenPGP/S/MIME, command palette, ricerca offline; verificare sorgente e licenza. |
| **Mailspring** | [GitHub](https://github.com/Foundry376/Mailspring) | Separazione tra UI e motore di sync; plugin, snooze, send later, regole. |
| **Geary** | [GitLab](https://gitlab.gnome.org/GNOME/geary) | Threading, visualizzazione conversazioni e UX essenziale. |
| **KMail / Kontact** | [GitHub](https://github.com/KDE/kmail) | Integrazione posta, calendario, MIME e crittografia. |
| **Evolution** | [GitLab](https://gitlab.gnome.org/GNOME/evolution) | iCalendar, RSVP, contatti, gestione avanzata delle caselle. |

### 10.4 Benchmark proprietari (UX e funzionalità; non codice da riutilizzare)

| Prodotto | Link | Motivo di interesse |
|---|---|---|
| **Briskmail** | [Sito](https://briskmail.app/) | AppleScript, Siri/Shortcuts, CLI, scorciatoie Gmail, outbox e integrazione macOS. |
| **bytemail** | [Funzionalità](https://bytemailapp.com/features) | Undo send, snooze, unsubscribe, antitracking, Smart Tabs e workflow da tastiera. |

Mimestream è già nella shortlist (sezione 9) ed è quindi intenzionalmente non duplicato in questa tabella.

## 11. Analisi UI/UX — riferimenti per la fase futura

Stato: benchmark e indirizzo progettuale, non decisione di redesign. Il fork di MishMail rimane la base applicativa candidata (DEC-007). Non si assume che la sua interfaccia sia quella definitiva: prima di modificarla, confrontare applicazioni in uso reale su macOS, non solo screenshot e liste di funzionalità. Le valutazioni sottostanti sono qualitative e preliminari, non risultati di test comparativi sistematici.

### 11.1 Classifica di riferimento (UX macOS per Gmail)

| Posizione indicativa | Applicazione | Punti di forza UX da studiare | Limiti dell'analisi |
|---|---|---|---|
| **1 — Mimestream** | [Sito](https://mimestream.com/) | Migliore riferimento **complessivo** per tradurre Gmail in convenzioni macOS: layout a tre pannelli, densità informativa, label e colori, conversazioni, toolbar, menu contestuali, navigazione mouse/tastiera. | Proprietario; valutazione basata su materiale pubblico e recensioni, da validare con prova diretta. |
| **2 — Briskmail** | [Sito](https://briskmail.app/) | Workflow desktop, shortcut Gmail, AppleScript/Shortcuts, automazioni e integrazione macOS. | Meno riscontri indipendenti sulla qualità d'uso quotidiana. |
| **3 — bytemail** | [Funzionalità](https://bytemailapp.com/features) | UI compatta e moderna, azioni rapide, snooze, undo send, unsubscribe e produttività. | Verificare ergonomia, comportamento effettivo e supporto delle funzioni dichiarate. |
| **4 — MishMail** | [GitHub](https://github.com/ronboger/mishmail) | Riferimento open source: command palette, navigazione keyboard-first, viste salvate e flussi di produttività. | Potenzialmente meno rifinito dei prodotti commerciali; richiede test e audit dell'interfaccia. |

Sintesi: Mimestream come benchmark UI/UX primario, Briskmail per shortcut e integrazioni macOS, bytemail per workflow e interazioni compatte, MishMail per base implementativa e funzionalità avanzate. Postie resta un riferimento tecnico di confronto, non il benchmark estetico principale.

### 11.2 Principi UX proposti per il nostro client

- Nativo prima di tutto: selezioni multiple, drag & drop, menu, toolbar, focus, scorciatoie, menu contestuali e accessibilità coerenti con macOS; ricorrere ad AppKit quando SwiftUI non offre comportamento desktop adeguato.
- Gmail senza sembrare una web app: rappresentare esplicitamente thread, label multiple, colori e ricerca Gmail, ma con finestre e controlli macOS.
- Densità configurabile: molte conversazioni visibili senza sacrificare leggibilità; prevedere anteprima, dimensioni pannelli e preferenze di visualizzazione.
- Mouse e tastiera di pari livello: shortcut Gmail, command palette e azioni rapide, senza nascondere operazioni fondamentali agli utenti mouse.
- Feedback immediato: indicatori chiari per sincronizzazione, attività offline, invio in coda/undo send, snooze, esito di operazioni sulle label e problemi OAuth.
- Sicurezza e fiducia: segnalare allegati, mittenti, messaggi cifrati/firmati, contenuti remoti bloccati e stato PGP in modo comprensibile.
- Personalizzazione ragionata: evitare di replicare automaticamente ogni dettaglio del layout MishMail o Gmail Web; preferire convenzioni e controlli utili nell'uso quotidiano del Mac.

### 11.3 Piano di confronto UX prima del redesign

☐ Installare e provare Mimestream, Briskmail e bytemail (quando disponibili in prova) e compilare/eseguire MishMail.
☐ Confrontare lo stesso set di attività: triage inbox, selezione multipla, archiviazione, label e colori, ricerca, composer, allegati, navigazione tra thread, snooze e undo send.
☐ Misurare numero di click/tasti, scoperta delle azioni, feedback, prestazioni percepite, densità e prevedibilità del focus.
☐ Verificare VoiceOver, navigazione completa da tastiera, contrasto, modalità scura, dimensionamento finestre e gestione di mailbox grandi.
☐ Catalogare pattern da mantenere, da adattare e da evitare, con screenshot e brevi note (non copiare asset proprietari).
☐ Prototipare soltanto i punti critici in SwiftUI/AppKit, poi valutare il costo di integrazione nel fork.
☐ Formalizzare un'eventuale decisione successiva (nuovo ADR) prima di intraprendere una riscrittura significativa della UI.

Collocazione nella roadmap: eseguire il confronto ergonomico durante Milestone 1–3; concentrare eventuale rifinitura sostanziale nella Milestone 5 — Qualità desktop, senza bloccare l'avanzamento delle funzionalità Gmail/ICS/PGP.

## 12. Security audit del fork (baseline)

Fonte: rapporto Codex SECURITY_AUDIT.md, fornito integralmente nella conversazione. **Il file non è nel repository:** va aggiunto (o collegato) perché questo documento lo indica come fonte di dettaglio.
Repository: bateman/mishmail
Commit esaminato: 18294fa653524cf02a77ddfd0e34db64b8fc09b2 (main)
Data audit: 22 novembre 2026 (UTC)
Metodo: sola lettura del codice, ricerche statiche mirate, controlli sintattici e prove sintetiche isolate su Linux. Nessun test nativo macOS né uso di credenziali o account reali.
Tracciabilità: tutti i riferimenti a file e righe sotto si riferiscono solo al commit esaminato; dopo modifiche dovranno essere rivalutati.
Revisioni precedenti: il repository contiene già `docs/security-review.md` e `docs/security-review-2026-07-29.md`, non considerate dall'audit. Vanno confrontate con i finding per individuare sovrapposizioni e rilievi già chiusi.
Controllo a campione (v0.7): i riferimenti di riga di F-01, F-02, F-07 e il percorso allegati di F-04 corrispondono al codice del commit auditato.

### 12.1 Esito e interpretazione

12 finding: 1 High, 8 Medium, 3 Low; 0 Critical dimostrati. Severità condizionate dai prerequisiti descritti. Le debolezze sono state identificate nei flussi sorgente, non sono exploit riprodotti su macOS, né prova di compromissione del canale di rilascio.

Il rischio principale riguarda la fiducia iniziale dell'updater per build firmate ad hoc: accetta qualunque publisher Developer ID notarizzato se l'app installata non possiede un Team ID. È necessario il compromesso del canale di release o metadata malevoli. Il canale attualmente configurato è ronboger/mishmail, non bateman/mishmail. Le installazioni già firmate con Team ID richiedono corrispondenza del Team ID ancorato ad Apple.

Una build locale Xcode firmata ad hoc è esattamente lo scenario di F-01, e l'updater avvia da solo controlli orari all'avvio dell'app (`App/MishMailApp.swift:153`). Il rischio è quindi attuale già in sviluppo, non solo in distribuzione.

Le lacune privacy confermate riguardano: fallback scrivibile su database legacy in chiaro, logging pubblico con identificativi e corpi degli errori, persistenza di allegati e copie AI dopo la rimozione dell'account, trasporto HTTP remoto non vincolato per lo script di riepilogo AI. Inoltre, consenso host legacy e discovery dei modelli possono trasferire credenziali verso origini nuove senza approvazione adeguata.

### 12.2 Registro completo dei rilievi

| ID | Severità | Rilievo | Evidenza principale | Condizione/rischio |
|---|---|---|---|---|
| **F-01** | **High** | Updater non vincola il publisher nelle installazioni ad hoc | `Sources/MishMail/Support/UpdateChecker.swift:704–733` | Canale release compromesso + binario attacker-signed notarizzato; nessuna compromissione accertata. |
| **F-02** | Medium | Database legacy plaintext resta scrivibile durante conversione differita | `Sources/MishMail/Store/Database.swift:1077–1083` | Cache legacy + conversione busy/istanza concorrente; dati nuovi in chiaro. |
| **F-03** | Medium | Log espongono indirizzi account ed errori API non oscurati | `Sources/MishMail/Support/DiagnosticLog.swift:46–84` | Evento di errore, log condiviso/raccolto; nessuna perdita token dimostrata. |
| **F-04** | Medium | Rimozione account non elimina tutti gli allegati e chat AI | `Sources/MishMail/App/MailStore+Accounts.swift:65–106` | Allegato già aperto o conversazione AI contenente dati mail. |
| **F-05** | Medium | Summarizer CLI accetta destinazioni HTTP remote con contenuti mail/chiavi | `scripts/mcp-summarize.py:77–88` | Endpoint HTTP remoto configurato dall'utente; verificato con transport mock. |
| **F-06** | Medium | Consenso legacy per host AI trasferito a un host differente | `Sources/MishMail/UI/SettingsView.swift:2323–2329` | Record legacy host-only + modifica host dell'utente. |
| **F-12** | Medium | Fetch models invia credenziali salvate a endpoint modificato non approvato | `SettingsView.swift:2340–2341,2423–2428`; `Support/LLMClient.swift:460–471` | Utente cambia endpoint, usa discovery; key/token provider riutilizzato. |
| **F-07** | Medium | Updater da terminale permette rollback a release vecchia firmata | `scripts/update-mishmail.sh:66–71` | Metadata release malevoli/obsoleti + uso script di aggiornamento. |
| **F-08** | Medium | Download/estrazione update privi di limiti di risorse applicativi | `Support/UpdateChecker.swift:403–405,567–575` | Archivio malevolo consegnato; traversal non dimostrato. |
| **F-09** | Low | Listener OAuth senza timeout e limite per connessione | `Auth/OAuth.swift:276–278,384–400` | Flood da processo locale durante login. |
| **F-10** | Low | Provenienza build, action CI e permessi non sufficientemente fissati | `.github/workflows/ci.yml:15–76`; `project.yml:8–10` | Compromissione di input CI/toolchain; nessuna CVE della dipendenza accertata. |
| **F-11** | Low | Anteprime notifiche replicano dati mail fuori dalla cache cifrata | `App/MailStore+Sync.swift:415–418`; `Support/Notifier.swift:11–16` | Notifiche abilitate e configurazione anteprime del sistema. |

### 12.3 Dettagli e remediation per finding

F-01 — Trust dell'updater (High). Se manca il runningTeam, la validazione verifica Developer ID e notarizzazione ma non uno specifico publisher; officialRelease non costituisce un vincolo effettivo. Il checksum, quando presente, proviene dallo stesso canale release. Lo script e l'app puntano all'upstream ronboger/mishmail. Correzione: per build locali ad hoc, disabilitare la sostituzione automatica dell'app. Per la distribuzione, configurare esplicitamente canale del fork, identità applicativa, requisito di firma Apple oppure chiave di aggiornamento indipendente; mantenere controlli notarizzazione, firme annidate, checksum e anti-rollback. L'accesso a Keychain da un eventuale sostituto resta una decisione separata del sistema operativo.

F-02 — Plaintext legacy (Medium). In caso di conversione occupata/disabilitata, Database.swift:1077–1083 sceglie .plaintext, omette usePassphrase e apre un DatabasePool scrivibile (:768–796). Correzione: bloccare la scrittura e la sincronizzazione di posta reale finché la conversione cifrata non completa; prevedere, se necessario, sola lettura di recupero. Testare migrazione con istanze concorrenti, quick_check, header e impossibilità di leggere schema/WAL senza chiave.

F-03 — Diagnostica (Medium). DiagnosticLog.swift:46–62 pubblica account, endpoint e fino a 4.000 caratteri del body HTTP via log privacy: .public e file testuale; non è provato che contenga token. Correzione: usare codici stato/categorie, endpoint parametrizzati, mascheramento/hashing degli account; niente body grezzi per default; permessi 0700/0600, retention esplicita e modalità diagnostica opt-in temporanea.

F-04 — Retention dopo rimozione (Medium). MailStore.swift:4447–4490 crea allegati in temporaryDirectory/MishMailAttachments/...; la rimozione account elimina token e righe principali ma non quell'albero né le conversazioni AI che possono includere risultati di get_thread (AskMishController.swift:1183–1204). Correzione: cleanup protetto da symlink e scadenza cache, metadati di provenienza account/thread per chat AI, scelta esplicita su cancellazione/retention, rimozione notifiche; considerare copie in backup e cache OS.

F-05 — HTTP helper AI (Medium). mcp-summarize.py:77–88,125–136 può inviare e-mail e bearer API key a --api-base HTTP remoto, aggirando le regole native; prova sintetica con dummy e mock, senza rete reale. Correzione: HTTP solo su loopback letterale, HTTPS da remoto, validazione redirect e flag di consenso per contenuti mail remoti; chiavi fuori da argomenti CLI, file sensibili 0600.

F-06 — Consenso legacy (Medium). In SettingsView.swift:2323–2329, il consenso salvato per il vecchio host può restare vero dopo cambio dell'URL; il salvataggio persiste quindi il consenso per il nuovo endpoint. Correzione: consentire migrazione solo a origin originale validata, azzerare consenso dopo variazione origin/scheme/porta e ricontrollare al salvataggio; regression test del caso legacy.

F-12 — Discovery credenziali (Medium). Fetch models può essere attivo con consenso disabilitato; costruisce una richiesta con ID provider già salvato a un URL modificato. LLMClient.listModels applica autenticazione senza controllo del consenso host, permettendo invio della chiave salvata. Correzione: associare i segreti all'origin autorizzata e applicare il controllo condiviso prima di ogni richiesta autenticata (discovery, test e generazione); non trasmettere credenziali a host nuovo fino a nuova autorizzazione; test che confermi zero chiamate al transport.

F-07 — Anti-rollback CLI (Medium). update-mishmail.sh:66–71 blocca solo versioni uguali; può sostituire una versione nuova con una vecchia ancora firmata. Correzione: confronto numerico autenticato NEW_VERSION > CURRENT, coerente con updater nativo; downgrade soltanto con opzione di recovery esplicita; controllo di bundle ID e signing requirement.

F-08 — Bounded extraction (Medium). UpdateChecker.swift:403–405,567–575 scarica ed estrae ZIP con ditto senza limiti applicativi di byte, numero entry, dimensione espansa, tempo o spazio disponibile. Correzione: limiti imposti durante il download e la decompressione, estrazione in directory privata, controllo path e symlink, deadline e riserva disco. Non è stato dimostrato un path traversal o un exploit di ditto.

F-09 — OAuth listener (Low). Il listener su 127.0.0.1 ha stato e PKCE robusti, ma le singole connessioni non hanno deadline/concurrency cap. Correzione: limite connessioni, deadline di lettura, tracking e cancel alla fine del login; test sintetici di client locali lenti.

F-10 — Supply chain (Low). actions/*@v4 è mutabile, xcodegen Homebrew non è fissato, workflow CI non specifica permissions:. Dipendenza GRDB/SQLCipher selezionata come binario: manifest 3.0.0 con checksum 41f01022f6a35986393e063e1ef386fd896646ed032f7d0419c4b02fa3afe61d, tag risolto 46098847eeabdb008f238bef5750a8e64097b6ed; binary non verificato e nessuna CVE asserita. Correzione: permessi contents: read, commit SHA per le action, toolchain pinned, dependency lock/provenance e SBOM binario.

F-11 — Notifiche (Low). UNMutableNotificationContent conserva mittente, oggetto o snippet fuori dal database SQLCipher; l'esposizione dipende dalle preferenze macOS. Correzione: anteprima generica "Nuova e-mail" come default privacy, opt-in separati, ID notifiche legati all'account e pulizia alla sua rimozione.

### 12.4 Controlli di sicurezza osservati nel codice

Il rapporto non ha dimostrato l'assenza delle protezioni principali; ha invece confermato in sorgente:

1. OAuth: PKCE S256, verifier casuale 64 byte, state 32 byte, confronto dello state su callback riusciti e d'errore, browser di sistema, loopback 127.0.0.1 e limite request-line 16 KiB (Auth/OAuth.swift).
2. Token: refresh coalescente con controllo di generazione, margine scadenza; Keychain non sincronizzato AfterFirstUnlockThisDeviceOnly; accessibilità e ACL da verificare su macOS (GmailClient.swift, AccessTokenCache.swift, Keychain.swift).
3. Storage: chiave casuale 256 bit in Keychain, usePassphrase, tabelle temporanee in RAM, procedure di export/quick_check per migrazione; resta l'eccezione F-02 e manca verifica del codec binario (Database.swift).
4. HTML/WebKit: content JavaScript disabilitato, CSP trusted-first che blocca script, form, frame e oggetti, storage effimero, blocco immagini remote di default, controllo navigazione e reset WebView; CSS/phishing e caricamento immagini approvato restano rischi inerenti (HTMLBodyCSP.swift, WebViewPool.swift).
5. MIME/allegati: basename, header folding, cache con permessi privati, file regolari e controllo symlink, scritture atomiche, avviso estensioni pericolose e tentativi di quarantena; successo di quarantine non verificato (MessageParsing.swift, MailStore.swift).
6. MCP locale: bind loopback, bearer token non vuoto, limiti di richiesta/connessione/lettura, identificazione token a tempo costante, API opt-in; client autenticati hanno intenzionalmente ampio accesso alla posta (MCPServer.swift).
7. Updater nativo: firma annidata e multiarchitettura, continuità Team ID per app già firmate, notarizzazione, signed bundle/tag match e controllo versione numerico; eccezioni F-01, F-07, F-08.
8. Sandbox e AI: sandbox per app e network entitlements; distribuzione con hardened runtime, helper di rilancio intenzionalmente non sandboxed; controllo consenso per generazione AI e conferma delle azioni di scrittura, ma le lacune F-05/F-06/F-12 permangono.
9. Gmail API: base HTTPS fissa, parametri codificati, retry limitati, rate pacing, refresh 401, gestione Retry-After; attenzione allo scope gmail.settings.basic abilitato anche per lettura filtri.
10. Unsubscribe: sessione effimera e validazione URL/redirect con esclusione indirizzi locali/credenziali; DNS che risolve a indirizzi privati rimane ipotesi da verificare, non SSRF dimostrata.

### 12.5 Evidenza dei controlli eseguiti e limitazioni

| Verifica | Risultato / significato |
|---|---|
| Inventario sorgente | 702 file tracked; 222 Swift sorgente e 219 Swift test (il rapporto indicava 214; corretto nella v0.7). Ricognizione per confini di sicurezza, non revisione di ogni riga. |
| Python | 7 script parsed con `ast.parse`; nessuna esecuzione dei main. |
| Shell | 7 script `bash -n` superati; nessuna prova operativa di update. |
| Plist/entitlements | 5 file sintatticamente letti; distribuzione firmata non verificata. |
| Probe F-05 | `summarize_openai` accetta URL HTTP remoto e prepara richiesta con key e mail sintetiche; trasporto mocked. |
| Probe F-06 | Predicato legacy consente host nuovo nel caso costruito; UI macOS non eseguita. |
| Probe F-07 | La condizione di uguaglianza lascia proseguire downgrade 0.7.0 → 0.6.0; nessun download. |
| Secret scan limitato | Nessun pattern PEM/GitHub token/AWS AKIA/Google API key rilevato nel testo selezionato; non prova completa assenza. |
| Toolchain native | Swift/Xcode/xcodegen/SwiftLint/Semgrep/ShellCheck non disponibili su Linux; XCTest, firma, notarizzazione, WKWebView, Keychain e APFS **non testati**. |
| Dipendenza binaria | Manifest e checksum ispezionati, non scaricato/verificato il framework, né SBOM/CVE delle librerie incluse. |

Ipotesi da verificare in laboratorio macOS: cifratura effettiva SQLite/WAL e comportamento senza chiave; Keychain a schermo bloccato; restrizioni CSP/WebKit e redirect con credenziali; quarantena e symlink su APFS; signed-release identity, release channel e archive bounds; chiusura callback OAuth; backup, crash dump, notifiche e residui AI. L'audit non prova compromissione delle release, furto di token o exploit remoto da una e-mail.

## 13. Piano di remediation e PR — priorità prima delle feature

Regola: per ogni PR includere test di regressione, riferimenti ai finding, comportamento previsto, compatibilità con upgrade/migrazione, e prova su macOS. Le PR sono proposte, non già aperte o implementate. Il documento non cambia il codice del repository.

Le PR partono solo dopo la decisione GO su MishMail come base (Milestone 0). Se le funzioni AI e il server MCP venissero disattivati (questione aperta, sezione 7), PR-03 e la parte AI di PR-05 si ridurrebbero alla verifica della disattivazione.

| Ordine | PR proposta | Finding | Criterio minimo di accettazione |
|---|---|---|---|
| **P0 / PR-01** | Sicurezza release del fork | F-01, F-07 | Update automatico non sostituisce build ad hoc; canale non ereditato senza scelta esplicita; nessun rollback involontario. |
| **P0 / PR-02** | Fail-closed database legacy | F-02 | Nessuna scrittura di mail reali in plaintext; conversione busy produce stato sicuro e test con dati fixture. |
| **P0 / PR-03** | Segreti e consenso AI | F-05, F-06, F-12 | Mai inviare credenziale a origin differente senza autorizzazione; remote HTTP rifiutato nei CLI helper. |
| **P1 / PR-04** | Privacy diagnostica | F-03 | Niente body grezzi/account in log di default; permessi e retention verificati. |
| **P1 / PR-05** | Cancellazione completa account | F-04, F-11 | Allegati/AI/notifiche associati all'account rimossi o esplicitamente conservati per scelta utente. |
| **P1 / PR-06** | Limiti e hardening | F-08, F-09 | Risorse update limitate, connessioni OAuth bounded e cancellate. |
| **P2 / PR-07** | CI/provenance e release gate | F-10 | Permessi minimi, pinning, inventario binari e test native obbligatori, senza skip silenziosi. |

Vincolo di rilascio:

- **Prima dell'uso quotidiano di account Gmail reali:** updater disabilitato sulle build locali (DEC-009, mitigazione di F-01) e F-02, F-03, F-12 risolti o mitigati. La v0.6 rimandava F-01 alla distribuzione, ma l'updater è attivo anche sulle build ad hoc di sviluppo.
- **Prima della distribuzione o di update binari:** F-01 e F-07 risolti in modo completo (canale e identità del fork), insieme ai limiti di F-08.
- **Prima di abilitare i flussi AI in ambienti reali:** F-05 e F-06.

Validare tutto con app compilata e firmata su macOS. La correzione delle vulnerabilità non richiede di importare codice Postie.

## 14. Stato attuale, dipendenze e prossime verifiche

> Aggiornamento v0.8: le PR di remediation sono state eseguite come ondate 1 e 2 del [piano di sviluppo](piano-sviluppo.md), che ne riporta l'esito per finding. L'elenco sotto è quello della v0.7 e resta come traccia.

☑ Audit statico a commit fisso ricevuto, con 12 finding documentati e 0 Critical dimostrati.
☑ Verificato il 23 novembre 2026 che il `main` del fork è ancora a `18294fa`; da ripetere prima di iniziare le PR.
☑ Confronto del documento con il codice del fork (v0.7): corretti stato delle funzionalità, stack e ordine della roadmap.
☐ Eseguire build macOS e test esistenti; confermare che i smoke test di firma/updater non siano saltati.
☐ Decisione GO/NO-GO su MishMail come base.
☐ Decidere su AI/MCP e sul rapporto con l'upstream (sezione 7), perché cambiano l'ampiezza delle PR.
☐ Disabilitare l'updater (DEC-009) e dare al fork identità propria (Milestone 1).
☐ Implementare PR-01/02/03, poi PR-04/05/06/07 in base ai rischi reali e all'uso previsto.
☐ Ripetere regression test di OAuth, SQLCipher, rendering HTML, allegati, AI, update e cancellazione account.
☐ Aggiungere `SECURITY_AUDIT.md` al repository e confrontarlo con le revisioni di sicurezza già presenti in `docs/`.
☐ Solo dopo, riprendere la milestone ICS/RSVP e la gap analysis rispetto a Postie.
☐ Prima di distribuzione: verificare entitlements finali, publisher identity, notarizzazione, provenance e policy OAuth Google.

Fonte canonica: questo documento unifica piano e risultati essenziali dell'audit del 22 novembre 2026. Il report originale SECURITY_AUDIT.md resta la fonte per formulazioni dettagliate, riferimenti di linea addizionali, prove sintetiche e ipotesi non risolte; in caso di divergenza sui rilievi, prevale l'evidenza al commit auditato, da rivalidare sul branch corrente.

## 15. Registro delle modifiche

| Data | Versione | Modifica |
|---|---|---|
| 2026-11-19 | 0.1 | Consolidate decisioni, requisiti, stack proposto e questioni aperte emerse nella conversazione. |
| 2026-11-22 | 0.2 | Aggiunti shortlist prioritaria (Postie, MacMail, MishMail, Exo, Thunderbird, Mimestream), checklist di analisi e backlog separato degli altri progetti open source e benchmark proprietari. |
| 2026-11-22 | 0.3 | Adottato indirizzo **fork MishMail + riuso selettivo Postie**, con criteri di audit, roadmap, condizioni GO/NO-GO, criteri di attribuzione e tracciamento delle integrazioni. |
| 2026-11-22 | 0.4 | Aggiunta analisi UI/UX per la fase futura: benchmark Mimestream, Briskmail, bytemail e MishMail; principi di design e checklist di confronto prima di eventuale redesign. |
| 2026-11-22 | 0.5 | Registrato il repository di sviluppo [bateman/mishmail](https://github.com/bateman/mishmail), distinto dall'upstream [ronboger/mishmail](https://github.com/ronboger/mishmail). |
| 2026-11-23 | 0.6 | Unificato piano di sviluppo e security audit del commit `18294fa`: 12 finding, controlli verificati in sorgente, limiti della verifica, DEC-008/009, priorità remediation e PR proposte. |
| 2026-11-23 | 0.7 | Confronto con il codice del fork. Corretti: stato reale delle funzionalità (ICS/RSVP, unsubscribe, shortcut, colori label, snooze, undo send e multi-account già presenti), stack (Swift 5.10, GRDB/SQLCipher, login loopback al posto di `ASWebAuthenticationSession`), scope `gmail.modify` restricted, conteggio dei test. Aggiunti: updater come prerequisito per gli account reali, identità del fork, GO/NO-GO prima delle remediation, questioni aperte su AI/MCP, upstream, snooze, Calendar e PGP, riferimenti alle revisioni di sicurezza esistenti. Nessuna nuova decisione confermata. |
| 2026-11-24 | 0.8 | Dopo le ondate 1 e 2 del piano di sviluppo: aggiunte DEC-010–016, DEC-009 segnata come implementata, chiusa la questione su AI e MCP. Lo stato di ogni finding e i seguiti sono in [piano-sviluppo.md](piano-sviluppo.md); i riferimenti di riga della sezione 12 valgono solo per il commit auditato `18294fa`. |
| 2026-11-24 | 0.9 | Aggiunte DEC-017–020: shortcut come Gmail Web, pannello di lettura predefinito, "cancellato vuol dire sparito", regola delle chat alla rimozione di un account. L'ondata 3 non è avviata. |
| 2026-11-24 | 0.10 | Dopo la prima prova su Mac: aggiunte DEC-021–024 (icone monocromatiche, correttore in più lingue, colori delle label come in Gmail, stile di comunicazione conciso). La cache persistente e cifrata delle immagini resta un'opzione in attesa delle prove del proprietario, annotata in [piano-sviluppo.md](piano-sviluppo.md). L'ondata 3 non è avviata. |
| 2026-11-24 | 0.11 | Terzo giro di richieste: aggiunte DEC-025–028 (colore della label dell'account, foto profilo Google, warning come errori in CI, icone della barra laterale). L'ondata 3 non è avviata. |
| 2026-11-24 | 0.12 | Quarto giro di richieste: aggiunte DEC-029–040 (forma delle label, anello e titolo dell'account, righe dei messaggi, cache cifrata delle immagini incorporate, immagini remote attive per impostazione predefinita, cache delle immagini remote, colore d'accento configurabile, modifiche semplici senza review, archiviazione e subentro dell'orchestratore, livelli di review, segnalazione di F-01 annullata, avvio dell'ondata 3). Aggiornata DEC-028. DEC-034 è decisa ma ancora in lavorazione (PR #42). L'ondata 3 non è avviata. |
| 2026-11-25 | **0.13** | Aggiunte DEC-041–046: snooze variante B, Google Calendar perimetro B, prima apertura delle immagini remote, avvio dell'ondata 4, PGP perimetro B, calendari per i conflitti scelti dall'utente. |
| 2026-11-25 | **0.14** | Aggiunta DEC-047: libreria OpenPGP rPGP (Rust), previa verifica che non esista una soluzione già pronta. |
| 2026-11-25 | **0.15** | Aggiunte DEC-048 (Calendar: permesso ampio) e DEC-049 (risposta agli inviti sempre su calendario e per e-mail). |
| 2026-11-25 | **0.16** | Aggiunta DEC-050: libreria OpenPGP in un repository separato. |
| 2026-11-25 | **0.17** | Aggiunte DEC-051 (Ed448/X448 e algoritmi deboli rifiutati, avvisi accettati), DEC-052 (e-mail prima del calendario), DEC-053 (badge dei non letti sulla foto profilo). |
| 2026-11-25 | **0.18** | Aggiunte DEC-054 (nel dubbio, come fa Gmail), DEC-055 (firme per account), DEC-056 (impostazioni per account). |
| 2026-11-25 | **0.19** | Aggiunte DEC-057 (barra laterale come Gmail e barra degli account), DEC-058 (`make run` con l'account reale), DEC-059 (rilasci della libreria OpenPGP). |
| 2026-11-25 | **0.20** | Aggiunta DEC-060 (libreria OpenPGP collegata anche a interruttore spento; caricamento dinamico da valutare). |
| 2026-11-25 | **0.21** | Aggiunte DEC-061 (nomi del rebranding a DreaMail) e DEC-062 (Chat e Calendar integrati: solo studio). |
| 2026-11-25 | **0.22** | Aggiunta DEC-063 (barra laterale come Gmail: scostamenti). |
| 2026-11-25 | **0.23** | Aggiunta DEC-064 (OpenPGP: regole di fiducia e formati). |
| 2026-11-25 | **0.24** | Aggiunte DEC-065 (rebranding: si fa), DEC-066 (Chat: account personali), DEC-067 (Calendar: solo pannello), DEC-068 (difetto di rPGP da segnalare). |
| 2026-11-25 | **0.25** | Aggiunta DEC-069 (rinomina in DreaMail eseguita); repository di sviluppo `bateman/dreamail`. |
| 2026-11-25 | **0.26** | Aggiunta DEC-070 (firme: seguono Gmail da sole; predefinita solo per i nuovi messaggi). |
| 2026-11-25 | **0.27** | Aggiunta DEC-071 (etichette: menu come Gmail, colore di famiglia; affina DEC-023). |
| 2026-11-26 | **0.28** | Aggiunta DEC-072 (prima sincronizzazione progressiva; accesso che finisce al salvataggio dell'account). |
| 2026-11-26 | **0.29** | Aggiunta DEC-073 (categorie senza sotto-menu; tasti alla finestra aperta). |
| 2026-11-26 | **0.30** | Aggiunta DEC-074 (firma ricca mostrata una volta sola; firma di Gmail incollabile). |
| 2026-11-26 | **0.31** | Aggiunte DEC-075 (ordine della barra laterale; "More" chiuso nasconde tutto) e DEC-076 (densità di elenco e barra laterale). |
| 2026-11-26 | **0.32** | Aggiunta DEC-077 (la selezione resta nel colore accent senza fuoco). |
| 2026-11-26 | **0.33** | Aggiunta DEC-078 (etichette sotto "More" senza doppioni; snooze con nomi inglesi). |
| 2026-11-26 | **0.34** | Aggiunta DEC-079 (barra laterale ridotta a striscia di icone). |
| 2026-11-26 | **0.35** | Aggiunta DEC-080 (etichette: famiglie intere e ordine di Gmail), che sostituisce la parte etichette di DEC-078. |
| 2026-11-26 | **0.36** | Aggiunta DEC-081 (Cestino per messaggio; posta nuova in una conversazione cestinata). |
| 2026-11-27 | **0.37** | Aggiunta DEC-082 (selezione della barra laterale squadrata, senza trattino del fuoco). |
| 2026-11-27 | **0.38** | Aggiunta DEC-083 (pallino dell'etichetta sempre visibile nel tema scuro; riga "Current:" nel foglio dei colori). |
| 2026-11-27 | **0.39** | Aggiunta DEC-084 (Inbox mostra tutta la posta con l'etichetta Inbox, senza categorie nascoste). |
| 2026-11-27 | **0.40** | Aggiunta DEC-085 (inbox unificata disattivabile). |
| 2026-11-27 | **0.41** | Aggiunta DEC-086 (messaggi cancellati visibili a richiesta nella conversazione viva), che precisa DEC-019 e DEC-081. |
| 2026-11-27 | **0.42** | Aggiunta DEC-087 (etichette disegnate con il preset di colore di Gmail), che prosegue DEC-083 e precisa DEC-071. |
| 2026-11-27 | **0.43** | Aggiunta DEC-088 ("Move to inbox" e menu del clic destro come Gmail). |
| 2026-11-27 | **0.44** | Aggiunta DEC-089 (Promotions e Social disattivabili per account). |
| 2026-11-27 | **0.45** | Aggiunta DEC-090 (azioni sul singolo messaggio e apertura sui messaggi stellati). |
| 2026-11-27 | **0.46** | Aggiornata DEC-079: il campo di ricerca è nella barra in alto dell'elenco e il pulsante Search della striscia lo attiva senza riaprire la barra laterale (PR #113). |
| 2026-11-27 | **0.47** | Aggiunta DEC-091 (barra di selezione come Gmail ed etichette su più conversazioni). |
| 2026-11-28 | **0.48** | Aggiunta DEC-092 (colore delle etichette solo di Gmail; via il colore "solo su questo Mac"). |
| 2026-11-28 | **0.49** | Aggiunta DEC-093 (menu "⋮" del messaggio come Gmail, con la stampa). |

---

> **Regola di manutenzione:** ogni nuova decisione va aggiunta nella sezione 2 con un ID progressivo; le proposte restano distinte dalle decisioni confermate. Aggiornare anche il registro delle modifiche.
