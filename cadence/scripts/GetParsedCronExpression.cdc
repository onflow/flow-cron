import "FlowCronUtils"

access(all) fun main(cronExpression: String): FlowCronUtils.CronSpec? {
    return FlowCronUtils.parse(expression: cronExpression)
}