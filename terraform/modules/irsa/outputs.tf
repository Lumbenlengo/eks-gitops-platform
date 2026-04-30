output "api_service_role_arn" { value = aws_iam_role.api_service.arn }
output "worker_service_role_arn" { value = aws_iam_role.worker_service.arn }
output "cluster_autoscaler_role_arn" { value = aws_iam_role.cluster_autoscaler.arn }
output "sqs_queue_url" { value = aws_sqs_queue.main.url }
output "sqs_queue_arn" { value = aws_sqs_queue.main.arn }
output "sqs_dlq_url" { value = aws_sqs_queue.dlq.url }
output "dynamodb_table_name" { value = aws_dynamodb_table.items.name }
output "dynamodb_table_arn" { value = aws_dynamodb_table.items.arn }
