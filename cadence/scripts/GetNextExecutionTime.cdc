import "FlowCron"
import "FlowCronUtils"

access(all) fun main(cronExpression: String, afterUnix: UInt64?): UFix64? {
    let cronSpec = FlowCronUtils.parse(expression: cronExpression)
    if cronSpec == nil {
        return nil
    }
    let nextTime = FlowCronUtils.nextTick(spec: cronSpec!, afterUnix: afterUnix ?? UInt64(getCurrentBlock().timestamp))
    
    if nextTime == nil {
        return nil
    }
    
    return UFix64(nextTime!)
}