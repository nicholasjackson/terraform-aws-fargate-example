---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceDefaults
metadata:
  name: web
spec:
  protocol: http

---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceRouter
metadata:
  name: web
spec:
  routes:
    - match:
        http:
          pathPrefix: /admin
      destination:
        service: admin
