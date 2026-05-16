# wan-monitor-rollback.rsc
# Remove o wan-monitor.rsc do mikrotik.
# ==============================================================================
# Usage: /import scripts/wan-monitor-rollback.rsc
#
# NAO restaura o isp-monitor velho. Pra ter o monitor velho de volta:
#   /import mikrotik-dual-wan-ecmp.rsc
# ==============================================================================

:put "Removing wan-monitor..."

:do { /system scheduler remove [find name="wan-monitor"] } on-error={}
:do { /system script environment remove [find where name~"^WAN[12]v[46](Status|DownCount|UpCount)\$"] } on-error={}

:put "wan-monitor removed."
:put "  Scheduler wan-monitor removido"
:put "  Globals WAN[12]v[46](Status|DownCount|UpCount) removidos (12 globals)"
:put ""
:put "Pra restaurar isp-monitor velho: /import mikrotik-dual-wan-ecmp.rsc"
