{{- define "service.fullname" -}}
{{- default .Chart.Name .Values.service.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service.configName" -}}
{{- if .Values.config.name -}}
{{ .Values.config.name }}
{{- else -}}
{{ include "service.fullname" . }}-config
{{- end -}}
{{- end -}}

{{- define "service.secretName" -}}
{{- if .Values.secret.name -}}
{{ .Values.secret.name }}
{{- else -}}
{{ include "service.fullname" . }}-secrets
{{- end -}}
{{- end -}}

{{- define "service.labels" -}}
app: {{ include "service.fullname" . }}
managed-by: helm
environment: {{ .Values.env | quote }}
{{- with .Values.service.labels }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}

{{- define "service.ingressHost" -}}
{{- if .Values.ingress.host -}}
{{ .Values.ingress.host }}
{{- else -}}
{{- $domain := ternary .Values.domains.internal .Values.domains.public .Values.ingress.internal -}}
{{ printf "%s.%s-eks.%s" .Values.service.name .Values.env $domain }}
{{- end -}}
{{- end -}}
