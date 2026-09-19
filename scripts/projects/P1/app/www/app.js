/* Factura — front statique minimal. Aucun script inline : compatible avec
   une CSP « script-src 'self' ». Toutes les requêtes passent par /api/. */
(function () {
  "use strict";
  var API = "/api";
  var stateEl = document.getElementById("state");
  var tbody = document.querySelector("#invoices tbody");
  var form = document.getElementById("new-invoice");
  var feedback = document.getElementById("feedback");

  function euros(cents, cur) {
    return (cents / 100).toFixed(2) + " " + cur;
  }

  function refreshHealth() {
    fetch(API + "/health").then(function (r) {
      return r.json().then(function (j) { return { code: r.status, j: j }; });
    }).then(function (res) {
      var j = res.j;
      stateEl.textContent = "état : " + j.status + " (db " + j.db +
        ", redis " + j.redis + ", version " + j.version + ")";
      stateEl.className = "state " + (res.code === 200 ? "ok" : "ko");
    }).catch(function () {
      stateEl.textContent = "état : API indisponible";
      stateEl.className = "state ko";
    });
  }

  function refreshInvoices() {
    fetch(API + "/invoices?limit=20").then(function (r) {
      if (!r.ok) { throw new Error("HTTP " + r.status); }
      return r.json();
    }).then(function (rows) {
      tbody.innerHTML = "";
      rows.forEach(function (inv) {
        var tr = document.createElement("tr");
        [inv.number, inv.customer, euros(inv.amount_cents, inv.currency),
         inv.status, new Date(inv.created_at).toLocaleString("fr-FR")]
          .forEach(function (v) {
            var td = document.createElement("td");
            td.textContent = v;
            tr.appendChild(td);
          });
        tr.className = "st-" + inv.status;
        tbody.appendChild(tr);
      });
    }).catch(function (e) {
      tbody.innerHTML = "";
      var tr = document.createElement("tr");
      var td = document.createElement("td");
      td.colSpan = 5;
      td.textContent = "liste indisponible : " + e.message;
      tr.appendChild(td);
      tbody.appendChild(tr);
    });
  }

  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    var data = {
      customer: form.customer.value,
      amount: parseFloat(form.amount.value)
    };
    fetch(API + "/invoices", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data)
    }).then(function (r) {
      return r.json().then(function (j) { return { code: r.status, j: j }; });
    }).then(function (res) {
      if (res.code === 201) {
        feedback.textContent = "facture " + res.j.number + " créée, " +
          "export en cours";
        form.reset();
      } else {
        feedback.textContent = "erreur : " + (res.j.error || res.code);
      }
      setTimeout(refreshInvoices, 1500);
    }).catch(function (e) {
      feedback.textContent = "erreur réseau : " + e.message;
    });
  });

  refreshHealth();
  refreshInvoices();
  setInterval(refreshHealth, 10000);
  setInterval(refreshInvoices, 10000);
})();
