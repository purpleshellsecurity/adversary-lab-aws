output "budget_name" {
  value       = aws_budgets_budget.lab.name
  description = "Name of the monthly budget"
}
