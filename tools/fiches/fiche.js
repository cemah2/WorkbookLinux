/* Fiches interactives du Workbook Linux & DevOps.
 * Les réponses restent dans le navigateur (localStorage), clé par page et par item.
 * Aucune donnée n'est envoyée nulle part. Licence MIT.
 */
(function () {
  "use strict";
  var PREFIXE = "wbfiche:";
  var PAGE = document.body.dataset.page;
  var memoire = {};
  var stockageOk = true;
  try {
    localStorage.setItem(PREFIXE + "__test", "1");
    localStorage.removeItem(PREFIXE + "__test");
  } catch (e) {
    stockageOk = false;
  }

  function lire(cle) {
    try {
      var v = stockageOk ? localStorage.getItem(cle) : memoire[cle];
      return v ? JSON.parse(v) : null;
    } catch (e) { return null; }
  }
  function ecrire(cle, val) {
    var s = JSON.stringify(val);
    try {
      if (stockageOk) localStorage.setItem(cle, s); else memoire[cle] = s;
    } catch (e) { memoire[cle] = s; }
  }
  function effacerCle(cle) {
    try { if (stockageOk) localStorage.removeItem(cle); } catch (e) { /* rien */ }
    delete memoire[cle];
  }
  function toutesLesCles() {
    var cles = [];
    try {
      if (stockageOk) {
        for (var i = 0; i < localStorage.length; i++) {
          var k = localStorage.key(i);
          if (k && k.indexOf(PREFIXE) === 0 && k !== PREFIXE + "__test") cles.push(k);
        }
      }
    } catch (e) { /* rien */ }
    Object.keys(memoire).forEach(function (k) { if (cles.indexOf(k) < 0) cles.push(k); });
    return cles;
  }
  function cle(page, id) { return PREFIXE + page + ":" + id; }
  function telecharger(nom, contenu, type) {
    var blob = new Blob([contenu], { type: type });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = nom;
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }
  function aujourdhui() { return new Date().toISOString().slice(0, 10); }
  function bandeau(texte) {
    var p = document.createElement("p");
    p.className = "bandeau";
    p.textContent = texte;
    document.body.insertBefore(p, document.body.firstChild);
  }
  if (!stockageOk) {
    bandeau("Ce navigateur refuse le stockage local (navigation privée ?) : tes réponses " +
            "seront perdues en fermant la page. Exporte-les avant de partir.");
  }

  /* ------------------------------------------------------------------ index */
  if (PAGE === "index") {
    var resume = JSON.parse(document.getElementById("resume").textContent);
    var totalItems = 0, totalFaits = 0, totalJustes = 0, totalQcm = 0;
    document.querySelectorAll(".carte").forEach(function (carte) {
      var p = carte.dataset.page, r = resume[p];
      if (!r) return;
      var faits = 0, justes = 0;
      r.q.forEach(function (id) {
        var st = lire(cle(p, id));
        if (st && st.c && st.c.length) faits++;
        if (st && st.ok) justes++;
      });
      r.r.forEach(function (id) {
        var st = lire(cle(p, id));
        if (st && st.t && st.t.trim()) faits++;
      });
      var n = r.q.length + r.r.length;
      totalItems += n; totalFaits += faits; totalJustes += justes; totalQcm += r.q.length;
      carte.querySelector(".jauge span").style.width = (n ? Math.round(100 * faits / n) : 0) + "%";
      carte.querySelector(".carte-etat").textContent =
        faits ? faits + " / " + n + " répondus · QCM justes : " + justes + " / " + r.q.length : "";
      if (n && faits === n) carte.classList.add("complet");
    });
    document.querySelector(".progression").textContent =
      totalFaits + " / " + totalItems + " items répondus · " + totalJustes + " / " + totalQcm + " QCM justes";

    document.getElementById("sauver").addEventListener("click", function () {
      var data = {};
      toutesLesCles().forEach(function (k) {
        data[k] = stockageOk ? localStorage.getItem(k) : memoire[k];
      });
      telecharger("workbook-reponses-" + aujourdhui() + ".json",
                  JSON.stringify({ version: 1, date: new Date().toISOString(), data: data }, null, 1),
                  "application/json");
    });
    document.getElementById("restaurer").addEventListener("change", function (ev) {
      var f = ev.target.files[0];
      if (!f) return;
      f.text().then(function (txt) {
        var obj = JSON.parse(txt), n = 0;
        if (!obj || !obj.data) throw new Error("format inconnu");
        Object.keys(obj.data).forEach(function (k) {
          if (k.indexOf(PREFIXE) !== 0) return;
          try { if (stockageOk) localStorage.setItem(k, obj.data[k]); else memoire[k] = obj.data[k]; n++; }
          catch (e) { /* plein */ }
        });
        bandeau(n + " réponses restaurées.");
        setTimeout(function () { location.reload(); }, 800);
      }).catch(function (e) { bandeau("Restauration impossible : " + e.message); });
    });
    return;
  }

  /* ------------------------------------------------------------------ fiche */
  var manifeste = JSON.parse(document.getElementById("manifeste").textContent);
  var items = Array.prototype.slice.call(document.querySelectorAll("article.item"));

  function etat(article) { return lire(cle(PAGE, article.dataset.id)) || {}; }
  function sauver(article, st) { ecrire(cle(PAGE, article.dataset.id), st); majProgression(); }

  function cochees(article) {
    return Array.prototype.slice.call(article.querySelectorAll(".options input:checked"))
      .map(function (i) { return i.value; }).sort();
  }
  function reponse(article) {
    var r = article.querySelector(".options").dataset.rep;
    return r ? r.split(",") : [];
  }
  function badge(article) {
    var st = etat(article), e = article.querySelector(".etat"), t = "", cls = "";
    if (article.dataset.type === "qcm") {
      if (st.v) { t = st.ok ? "✓ juste" : "✗ à revoir"; cls = st.ok ? "ok" : "ko"; }
      else if (st.c && st.c.length) { t = "répondu"; cls = "fait"; }
    } else if (st.t && st.t.trim()) {
      t = st.vu ? "répondu · corrigé vu" : "répondu"; cls = "fait";
      if (st.k) t += " · check ✓";
    } else if (st.vu) { t = "corrigé vu"; cls = "vu"; }
    if (st.a) t += (t ? " · " : "") + st.a + (st.a > 1 ? " aides" : " aide");
    e.textContent = t;
    e.className = "etat " + cls;
  }
  function montrerCorrige(article, oui) {
    var c = article.querySelector(".corrige"), b = article.querySelector("button.voir");
    c.hidden = !oui;
    b.textContent = oui ? "Masquer le corrigé" : "Voir le corrigé";
    if (oui) { var st = etat(article); st.vu = true; sauver(article, st); badge(article); }
  }
  function marquer(article, ok) {
    var rep = reponse(article), ch = cochees(article);
    article.querySelectorAll(".option").forEach(function (o) {
      var l = o.dataset.l;
      o.classList.toggle("juste", rep.indexOf(l) >= 0);
      o.classList.toggle("faux", ch.indexOf(l) >= 0 && rep.indexOf(l) < 0);
    });
    var na = etat(article).a || 0;
    var avec = na ? " (avec " + na + (na > 1 ? " aides)" : " aide)") : "";
    article.querySelector(".verdict").textContent = ok ? "Juste !" + avec
      : "Pas tout à fait : la bonne réponse est " + rep.join(", ") + "." + avec;
    article.classList.toggle("reussi", ok);
    article.classList.toggle("rate", !ok);
  }
  function effacerMarques(article) {
    article.querySelectorAll(".option").forEach(function (o) { o.classList.remove("juste", "faux"); });
    article.classList.remove("reussi", "rate");
    article.querySelector(".verdict").textContent = "";
  }
  function verifier(article, silencieux) {
    var rep = reponse(article), ch = cochees(article);
    if (!rep.length) return null;
    if (!ch.length) {
      if (!silencieux) article.querySelector(".verdict").textContent = "Coche au moins une réponse.";
      return null;
    }
    var ok = rep.length === ch.length && rep.every(function (l, i) { return l === ch[i]; });
    var st = etat(article);
    st.c = ch; st.v = true; st.ok = ok;
    sauver(article, st);
    marquer(article, ok);
    montrerCorrige(article, true);
    badge(article);
    return ok;
  }
  function autoTaille(t) {
    t.style.height = "auto";
    t.style.height = Math.max(t.scrollHeight + 2, 110) + "px";
  }

  items.forEach(function (article) {
    var st = etat(article);
    if (article.dataset.type === "qcm") {
      article.querySelectorAll(".options input").forEach(function (inp) {
        if (st.c && st.c.indexOf(inp.value) >= 0) inp.checked = true;
        inp.addEventListener("change", function () {
          var s = etat(article);
          s.c = cochees(article); s.v = false; s.ok = false;
          sauver(article, s);
          effacerMarques(article);
          badge(article);
        });
      });
      if (st.v) { marquer(article, !!st.ok); }
      var bv = article.querySelector("button.verifier");
      if (bv) bv.addEventListener("click", function () { verifier(article, false); });
    } else {
      var ta = article.querySelector("textarea");
      var minuteur = null;
      ta.value = st.t || "";
      autoTaille(ta);
      ta.addEventListener("input", function () {
        autoTaille(ta);
        clearTimeout(minuteur);
        minuteur = setTimeout(function () {
          var s = etat(article); s.t = ta.value; sauver(article, s); badge(article);
        }, 400);
      });
      ta.addEventListener("blur", function () {
        var s = etat(article); s.t = ta.value; sauver(article, s); badge(article);
      });
      var ck = article.querySelector(".coche-check");
      if (ck) {
        ck.checked = !!st.k;
        ck.addEventListener("change", function () {
          var s = etat(article); s.k = ck.checked; sauver(article, s); badge(article);
        });
      }
    }
    /* aides progressives */
    var ba = article.querySelector("button.aide-suivante");
    if (ba) {
      var total = parseInt(ba.dataset.total, 10) || 0;
      var montrerAides = function (n) {
        article.querySelectorAll(".aide").forEach(function (a) {
          a.hidden = parseInt(a.dataset.n, 10) > n;
        });
        if (n >= total) {
          ba.disabled = true;
          ba.textContent = "Plus d'aide";
          ba.title = "Toutes les aides sont affichées : il reste le corrigé.";
        } else {
          ba.disabled = false;
          ba.innerHTML = "Aide " + (n + 1) + '<span class="sur"> / ' + total + "</span>";
        }
      };
      montrerAides(st.a || 0);
      ba.addEventListener("click", function () {
        var s = etat(article);
        s.a = Math.min((s.a || 0) + 1, total);
        sauver(article, s);
        montrerAides(s.a);
        badge(article);
        var nv = article.querySelector('.aide[data-n="' + s.a + '"]');
        if (nv && nv.scrollIntoView) nv.scrollIntoView({ block: "nearest", behavior: "smooth" });
      });
    }

    article.querySelector("button.voir").addEventListener("click", function () {
      var c = article.querySelector(".corrige");
      if (!c.hidden) { montrerCorrige(article, false); return; }
      var vide = article.dataset.type === "qcm" ? !cochees(article).length
        : !article.querySelector("textarea").value.trim();
      if (vide && !article.dataset.averti) {
        article.dataset.averti = "1";
        article.querySelector(".verdict").textContent =
          "Rien de répondu encore : cherche d'abord (règle des 20 minutes). Clique à nouveau pour l'afficher quand même.";
        return;
      }
      article.querySelector(".verdict").textContent = "";
      montrerCorrige(article, true);
    });
    badge(article);
  });

  /* QCM entier */
  document.querySelectorAll(".verifier-tout").forEach(function (b) {
    b.addEventListener("click", function () {
      var section = b.closest(".section") || document;
      var qs = section.querySelectorAll('article.item[data-type="qcm"]');
      var justes = 0, faits = 0, auto = 0;
      qs.forEach(function (a) {
        if (!reponse(a).length) return;
        auto++;
        var r = verifier(a, true);
        if (r !== null) { faits++; if (r) justes++; }
      });
      section.querySelector(".score-qcm").textContent = "Score : " + justes + " / " + auto +
        (auto - faits ? " (" + (auto - faits) + " sans réponse)" : "");
    });
  });

  /* auto-évaluation */
  document.querySelectorAll("input.ae").forEach(function (c) {
    var k = cle(PAGE, c.dataset.k);
    c.checked = !!lire(k);
    c.addEventListener("change", function () { if (c.checked) ecrire(k, 1); else effacerCle(k); });
  });

  function majProgression() {
    var q = 0, qj = 0, nq = 0, r = 0, nr = 0;
    manifeste.items.forEach(function (it) {
      var st = lire(cle(PAGE, it.id)) || {};
      if (it.type === "qcm") { nq++; if (st.c && st.c.length) q++; if (st.ok) qj++; }
      else { nr++; if (st.t && st.t.trim()) r++; }
    });
    var p = document.querySelector(".progression");
    if (p) p.textContent = "QCM : " + q + " / " + nq + " répondus, " + qj + " justes · réponses écrites : " + r + " / " + nr;
  }
  majProgression();

  /* export Markdown */
  document.getElementById("exporter").addEventListener("click", function () {
    var lignes = ["# Réponses — " + manifeste.label + " — " + manifeste.titre, "",
                  "_Exporté le " + aujourdhui() + " depuis les fiches interactives du workbook._", ""];
    var qcm = manifeste.items.filter(function (i) { return i.type === "qcm"; });
    if (qcm.length) {
      lignes.push("## QCM", "", "| Question | Ta réponse | Résultat | Aides |", "|---|---|---|---|");
      qcm.forEach(function (it) {
        var st = lire(cle(PAGE, it.id)) || {};
        var res = st.v ? (st.ok ? "juste" : "faux (attendu : " + (it.rep || []).join(", ") + ")") : "non vérifié";
        lignes.push("| " + it.code + " | " + ((st.c || []).join(", ") || "—") + " | " + res + " | " +
                    (st.a || 0) + " / " + (it.na || 0) + " |");
      });
      lignes.push("");
    }
    manifeste.items.forEach(function (it) {
      if (it.type === "qcm") return;
      var st = lire(cle(PAGE, it.id)) || {};
      lignes.push("## " + it.code, "");
      if (st.k) lignes.push("_Script check : réussi._", "");
      if (st.a) lignes.push("_Aides utilisées : " + st.a + " / " + (it.na || 0) + "._", "");
      lignes.push(st.t && st.t.trim() ? st.t.trim() : "_(pas de réponse)_", "");
    });
    var num = manifeste.page.slice(0, 2);
    var nom = (/^\d\d$/.test(num) ? "M" + num : manifeste.page.slice(0, 2)) + "-reponses.md";
    telecharger(nom, lignes.join("\n"), "text/markdown;charset=utf-8");
  });

  /* effacer la fiche (deux clics) */
  var be = document.getElementById("effacer"), armement = null;
  be.addEventListener("click", function () {
    if (!be.dataset.arme) {
      be.dataset.arme = "1";
      be.textContent = "Confirmer : tout effacer ?";
      armement = setTimeout(function () { delete be.dataset.arme; be.textContent = "Effacer cette fiche"; }, 4000);
      return;
    }
    clearTimeout(armement);
    toutesLesCles().forEach(function (k) { if (k.indexOf(PREFIXE + PAGE + ":") === 0) effacerCle(k); });
    location.reload();
  });

  /* diagrammes Mermaid (si le réseau le permet) */
  if (document.querySelector("pre.mermaid")) {
    var sombre = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    import("https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs").then(function (m) {
      m.default.initialize({ startOnLoad: false, theme: sombre ? "dark" : "default" });
      m.default.run({ querySelector: "pre.mermaid" });
    }).catch(function () { /* hors ligne : on garde le source */ });
  }
})();
