# Hacking guide

## Testing

Run a kubernetes cluster locally by e.g., `KUBECONFIG=$PWD/.kubeconfig k3d cluster create`.
When running rspec, give it `KUBECONFIG` environment variable as `KUBECONFIG=$PWD/.kubeconfig bundle exec rake spec`.
