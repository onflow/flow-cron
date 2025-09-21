import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowCronUtils"
import "FlowToken"
import "FungibleToken"
import "ViewResolver"
import "MetadataViews"

/// FlowCron: A handler that wraps any other handler adding cron scheduling functionality.
access(all) contract FlowCron {
    
    // The CronHandler resource is a wrapper around a handler and a cron expression
    access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {

        /// Cron expression for scheduling
        access(all) let cronExpression: String

        /// Cron spec for scheduling
        access(self) let cronSpec: FlowCronUtils.CronSpec
        /// The handler that performs the actual work
        access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        
        // Clear separation of concerns
        // The cronspec and wrapped handler are saved in the CronHandler resource
        // => they represent the purpose of the CronHandler resource and define it
        // The other data is passed in the context (data args on schedule)
        // => they represent the capability and data needed to execute the cron job
        init(
            cronExpression: String,
            wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        ) {
            self.cronExpression = cronExpression
            self.cronSpec = FlowCronUtils.parse(expression: cronExpression) ?? panic("Invalid cron expression: ".concat(cronExpression))
            self.wrappedHandlerCap = wrappedHandlerCap
        }
        
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?) {   
            // Extract execution context
            let context = data as? CronContext ?? panic("Invalid execution data: expected CronContext")

            // Calculate the future time at which the future transaction should be executed
            // 1 -> 2 -> 3 where 1 is this tx, 2 is already scheduled, 3 is the future tx that will be scheduled
            let nextTime = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: UInt64(getCurrentBlock().timestamp))
                ?? panic("Cannot find next execution time for cron expression")
            let futureTime = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: nextTime)
                ?? panic("Cannot find future execution time for cron expression")

            // Estimate fees
            let estimate = FlowTransactionScheduler.estimate(
                data: context,
                timestamp: UFix64(futureTime),
                priority: context.priority,
                executionEffort: context.executionEffort
            )
            if estimate.flowFee == nil {
                panic(estimate.error ?? "Failed to estimate transaction fee")
            }
            // Borrow fee provider and withdraw fees
            let feeVault = context.feeProviderCap.borrow()
                ?? panic("Cannot borrow fee provider capability")
            let fees <- feeVault.withdraw(amount: estimate.flowFee!)
            
            // Schedule future transaction to ensure continuity, next is always already scheduled (2 txs always scheduled)
            let schedulerManager = context.managerCap.borrow()
                ?? panic("Cannot borrow scheduler manager capability")
            // Use shortcut function to avoid passing the handler capability
            let futureTransactionId = schedulerManager.scheduleByHandler(
                handlerTypeIdentifier: self.getType().identifier,
                handlerUUID: self.uuid,
                data: context,
                timestamp: UFix64(futureTime),
                priority: context.priority,
                executionEffort: context.executionEffort,
                fees: <-fees as! @FlowToken.Vault
            )
            
            // Execute the wrapped handler at last so that even if it fails, the future transaction is scheduled
            // We use wrapped data so that it has the same exact usage as if it was executed normally
            let wrappedHandler = self.wrappedHandlerCap.borrow()
                ?? panic("Cannot borrow wrapped handler capability")
            wrappedHandler.executeTransaction(id: id, data: context.wrappedData)
        }
        
        /// ViewResolver implementation
        access(all) view fun getViews(): [Type] {
            var views: [Type] = [
                Type<MetadataViews.Display>(),
                Type<CronHandlerInfo>()
            ]
            
            // Add wrapped handler views if available
            if let handler = self.wrappedHandlerCap.borrow() {
                views = views.concat(handler.getViews())
            }
            return views
        }
        
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            let wrappedHandler = self.wrappedHandlerCap.borrow()
            switch view {  
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: "Cron Handler",
                        description: "Cron expression: ".concat(self.cronExpression).concat(" for handler: ").concat(wrappedHandler?.getType()?.identifier ?? ""),
                        thumbnail: MetadataViews.HTTPFile(url: "")
                    )
                case Type<CronHandlerInfo>():
                    let nextExecution = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: UInt64(getCurrentBlock().timestamp))
                    return CronHandlerInfo(
                        cronExpression: self.cronExpression,
                        nextExecution: nextExecution,
                        wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                        wrappedHandlerUUID: wrappedHandler?.uuid
                    )
                default:
                    return wrappedHandler?.resolveView(view)
            }
        }
    }

    /// Context passed to each cron execution (it's private in transaction data)
    /// It contains all the data that is needed for execution the cron handler, specific per scheduling run
    access(all) struct CronContext {
        access(all) let managerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
        access(all) let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let executionEffort: UInt64
        access(all) let wrappedData: AnyStruct?
        
        init(
            managerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>,
            feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64,
            wrappedData: AnyStruct?
        ) {
            self.managerCap = managerCap
            self.feeProviderCap = feeProviderCap
            self.priority = priority
            self.executionEffort = executionEffort
            self.wrappedData = wrappedData
        }
    }
    
    /// View structure for cron job information
    access(all) struct CronHandlerInfo {
        access(all) let cronExpression: String
        access(all) let nextExecution: UInt64?
        access(all) let wrappedHandlerType: String?
        access(all) let wrappedHandlerUUID: UInt64?
        
        init(
            cronExpression: String,
            nextExecution: UInt64?,
            wrappedHandlerType: String?,
            wrappedHandlerUUID: UInt64?
        ) {
            self.cronExpression = cronExpression
            self.nextExecution = nextExecution
            self.wrappedHandlerType = wrappedHandlerType
            self.wrappedHandlerUUID = wrappedHandlerUUID
        }
    }
    
    /// Create a new CronHandler resource
    access(all) fun createCronHandler(
        cronExpression: String,
        wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    ): @CronHandler {
        return <- create CronHandler(
            cronExpression: cronExpression,
            wrappedHandlerCap: wrappedHandlerCap
        )
    }
    
    init() {
        // No contract storage needed, each CronHandler manages itself
    }
}