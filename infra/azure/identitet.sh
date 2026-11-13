#!/usr/bin/env bash
# En identitet åt pipelinen, utan lösenord (M6). GitHub Actions loggar in i Azure med OIDC:
# jobbet får en kortlivad token av GitHub, och Azure litar på den – men bara för jobb som kör
# i repot REPO och miljön azure-staging, och bara med rätt att ändra resursgruppen RG.
# Körs EN gång per team, efter skapa-staging.sh. Skriver ut raderna för GitHub-miljön.
# Kan köras om: det som redan finns (din app registration, rollen, den federerade identiteten)
# återanvänds i stället för att ge fel.
#
#   REPO=<ägare>/<repo> ./infra/azure/identitet.sh      (kräver az + gh inloggade)
set -euo pipefail

: "${REPO:?Sätt REPO=<ägare>/<repo>}"
RG="${RG:-utpost-rg}"
APP="${APP:-utpost-staging}"
GH_ENV="${GH_ENV:-azure-staging}"
# Ägaren ingår i namnet. Flera team har ett repo som heter utpost, och alla i katalogen ser
# varandras app registrations – bara <repo>-github hade hittat ett annat teams identitet.
NAME="${NAME:-${REPO%%/*}-${REPO##*/}-github}"

SUB="$(az account show --query id --output tsv)"
TENANT="$(az account show --query tenantId --output tsv)"
ME="$(az ad signed-in-user show --query id --output tsv 2>/dev/null || true)"
SCOPE="/subscriptions/${SUB}/resourceGroups/${RG}"

echo "→ app registration + service principal: ${NAME}"
# Körs skriptet om återanvänds den app registration som redan finns – men bara om den är din
# (eller saknar ägare: skapad av en administratör som kört skriptet åt teamet).
APPID="$(az ad app list --display-name "${NAME}" --query '[0].appId' --output tsv)"
if [ -n "${APPID}" ]; then
  AGARE="$(az ad app owner list --id "${APPID}" --query "[].id" --output tsv 2>/dev/null || true)"
  if [ -n "${AGARE}" ] && [ -n "${ME}" ] && ! grep -qx "${ME}" <<< "${AGARE}"; then
    echo "FEL: det finns redan en app registration som heter ${NAME}, men den ägs av någon annan." >&2
    echo "     Är det en teamkamrat: identiteten är redan skapad – kör inte skriptet igen, be om raderna." >&2
    echo "     Annars: välj ett eget namn, NAME=<något-unikt>-github, och kör igen." >&2
    exit 1
  fi
  echo "   (finns redan – återanvänds)"
else
  APPID="$(az ad app create --display-name "${NAME}" --query appId --output tsv)"
fi
az ad sp show --id "${APPID}" --output none 2>/dev/null || az ad sp create --id "${APPID}" --output none
SPID="$(az ad sp show --id "${APPID}" --query id --output tsv)"
# Ger az ad app create "Insufficient privileges": du får inte skapa identiteter i den här katalogen –
# be den som administrerar prenumerationen köra skriptet (REPO=… RG=…), resten av flödet är oförändrat.

echo "→ rollen Contributor på BARA resursgruppen ${RG} (inte hela prenumerationen)"
har_rollen() {
  [ -n "$(az role assignment list --scope "${SCOPE}" --role Contributor --query "[?principalId=='${SPID}'] | [0].id" --output tsv)" ]
}
if har_rollen; then
  echo "   (finns redan)"
else
  FEL="$(mktemp)"
  TILLDELAD=""
  for i in 1 2 3 4 5 6; do
    # Finns tilldelningen redan svarar Azure RoleAssignmentExists – det är inget fel, därför kollas listan.
    if az role assignment create --role Contributor --assignee-object-id "${SPID}" --assignee-principal-type ServicePrincipal --scope "${SCOPE}" --output none 2>"${FEL}" || har_rollen; then
      TILLDELAD=ja; break
    fi
    echo "   (identiteten syns ofta inte direkt efter att den skapats – väntar 10 s, försök ${i}/6)"; sleep 10
  done
  if [ -z "${TILLDELAD}" ]; then
    cat "${FEL}" >&2
    echo "FEL: rolltilldelningen gick inte igenom. Utan den blir Deploy rött med AuthorizationFailed." >&2
    echo "     Kräver Owner eller User Access Administrator på resursgruppen – annars gör en administratör raden ovan." >&2
    exit 1
  fi
  rm -f "${FEL}"
fi

# GitHub skickar subject med id:n: repo:<ägare>@<ägar-id>/<repo>@<repo-id>:environment:<miljö>.
# Namn räcker inte: ett repo som döps om eller skapas på nytt med samma namn får inte logga in.
# gh (inloggad) i stället för anonym curl – GitHubs anonyma gräns delas av alla på samma nät.
REPO_ID="$(gh api "repos/${REPO}" --jq .id)"
OWNER_ID="$(gh api "repos/${REPO}" --jq .owner.id)"
SUBJECT="repo:${REPO%%/*}@${OWNER_ID}/${REPO##*/}@${REPO_ID}:environment:${GH_ENV}"
echo "→ federerad identitet, subject: ${SUBJECT}"
FC_NAME="github-${GH_ENV}"
FC="{\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"${SUBJECT}\",\"audiences\":[\"api://AzureADTokenExchange\"]}"
if az ad app federated-credential show --id "${APPID}" --federated-credential-id "${FC_NAME}" --output none 2>/dev/null; then
  az ad app federated-credential update --id "${APPID}" --federated-credential-id "${FC_NAME}" --parameters "${FC}" --output none
  echo "   (fanns redan – uppdaterad till subjectet ovan)"
else
  az ad app federated-credential create --id "${APPID}" --parameters "{\"name\":\"${FC_NAME}\",${FC#\{}" --output none
fi

FQDN="$(az containerapp show --name "${APP}" --resource-group "${RG}" --query properties.configuration.ingress.fqdn --output tsv)"
echo
echo "Klart. Lägg in på GitHub-miljön ${GH_ENV} (variables, inte secrets – ett id är ingen hemlighet):"
echo "  gh api -X PUT repos/${REPO}/environments/${GH_ENV} > /dev/null"
echo "  gh variable set AZURE_CLIENT_ID       --env ${GH_ENV} --repo ${REPO} --body ${APPID}"
echo "  gh variable set AZURE_TENANT_ID       --env ${GH_ENV} --repo ${REPO} --body ${TENANT}"
echo "  gh variable set AZURE_SUBSCRIPTION_ID --env ${GH_ENV} --repo ${REPO} --body ${SUB}"
echo "  gh variable set AZURE_RG              --env ${GH_ENV} --repo ${REPO} --body ${RG}"
echo "  gh variable set AZURE_APP             --env ${GH_ENV} --repo ${REPO} --body ${APP}"
echo "  gh variable set AZURE_URL             --env ${GH_ENV} --repo ${REPO} --body https://${FQDN}"
