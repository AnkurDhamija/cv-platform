{{/* Deploy-by-digest image ref; falls back to tag when digest is empty. */}}
{{- define "cvp.image" -}}
{{- if .digest -}}
{{ .repository }}@{{ .digest }}
{{- else -}}
{{ .repository }}:{{ .tag }}
{{- end -}}
{{- end -}}
