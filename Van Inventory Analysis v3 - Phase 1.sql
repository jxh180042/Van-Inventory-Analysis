declare @startdate date, @enddate date
set @startdate = getdate()-365
set @enddate = getdate()




;with cte_TechPartUsage(itemid,itemdesc,sumQty,sumAmount,lineCount)
as(
--Parts
                SELECT   
                                                sl.ITEMID,
                                                sl.name,
                                                sum(sl.QTYORDERED) 'SumQTY',
                                                sum(sl.LINEAMOUNT) 'SumAmount',
                                                sum(case when sl.SALESQTY > 0 then 1 else -1 end) 'LineCount'
                FROM            dbo.SALESTABLE AS st 
                                                                                                                 left join salesline sl on sl.SALESID = st.SALESID
                                                                                                                left JOIN INVENTTABLE AS erp ON erp.ITEMID = sl.ITEMID 
                                                                                                                 left JOIN dbo.XAP_NPRITEM AS npr ON npr.PRODUCT = erp.PRODUCT																											
                                                                                                                left JOIN dbo.XAP_SOURCEOFSUPPLY AS sos ON npr.SOSRECID = sos.RECID 
                                                                                                                 left JOIN dbo.CUSTTABLE AS ct ON st.INVOICEACCOUNT = ct.ACCOUNTNUM 
                                                                                                                 left JOIN dbo.ECORESPRODUCTTRANSLATION AS erpt ON erpt.PRODUCT = npr.PRODUCT 
                                                                                                                 left JOIN dbo.DIRPARTYTABLE AS cust ON ct.PARTY = cust.RECID
                                                                                                                left join INVENTTABLEMODULE price on price.ITEMID = sl.ITEMID and price.MODULETYPE =0
                                                                                                                left join XAP_ORDERCLASS oc on oc.RECID = st.ORDERCLASSRECID
                                                                                                                left join INVENTLOCATION il on il.inventlocationid = st.INVENTLOCATIONID
                                                                                                                left join DEFAULTDIMENSIONVIEW ddv on il.DEFAULTDIMENSION = ddv.DEFAULTDIMENSION                
                                                                                                                inner join XAP_SVCCALLTABLE svc on svc.RECID = st.SVCCALLRECID
                                                                                                                LEFT join HCMWORKER wrker on svc.WRKCTRID = wrker.PERSONNELNUMBER
                                                                                                                inner join projinvoicejour pij on pij.SVCCALLID = svc.RECID
                                LEFT join DIRPARTYTABLE dir on wrker.PERSON = dir.RECID
                WHERE        (st.ORDERCLASSRECID in (5637144580))
                AND (npr.ITEMDATAAREAID = 'BRG')
                and sos.SOS is not null
                --and st.SALESSTATUS = 3
                and svc.CALLOPENSTATUS = 0
                and ddv.displayvalue is not null
                and st.CREATEDDATETIME between @startdate and @enddate
                and wrker.PERSONNELNUMBER = @workerid
                group by sl.ITEMID,sl.NAME 
),cte_VanInventory(itemid,itemdesc,AvailPhys,wmslocationid)
as(
                select ItemID
                                                ,name
                                                ,AvailPhys
												,wmslocationid
                from [BriggsAX].[dbo].cache_BriggsPartsInventory 
                where inventsiteid = 'VAN' 
                and InventlocationId = @vanwarehouse
                and WMSLocationId = @vannumber
              --  and AvailPhys <> 0
				--AND AvailPhys is NOT NULL
),cte_BinAndCost(cost,itemid,availphys,stockedstatus,wmslocationid,saledate,defaultbin,min,max)
as(
--Bins and Costs

				select cost
								,ItemID
								,AvailPhys
								,stockedstatus
								,wmslocationid
								,saledate
								,defaultbin
								,min
								,max

				from [BriggsAX].[dbo].cache_BriggsPartsInventory
				where InventlocationId = @mainwarehouse
				and DefaultBin = 'Yes'
				
)
select			 isnull(tpu.itemid,vi.itemid) 'Item ID'
                ,isnull(tpu.itemdesc,vi.itemdesc) 'Item Name'
				
                ,cast(isnull(tpu.sumQty,0) AS int) 'Qty Sold'
               -- ,tpu.sumAmount
                ,isnull(tpu.lineCount,0) 'Times Sold'
                ,cast(isnull(vi.AvailPhys,0) AS int) 'Van Count'
				,case 
							when isnull(bc.cost,0) > 150 and isnull(vi.AvailPhys,0) = 0 then 'Do not add to van'
							when isnull(bc.cost,0) > 150 and isnull(vi.AvailPhys,0) > 0 then 'Remove from van- add to warehouse'
							when isnull(tpu.linecount,0) IN(0,1,2) and isnull(vi.AvailPhys,0) = 0 then 'Do not add to van'
							when isnull(tpu.lineCount,0) IN(0,1) and isnull(vi.AvailPhys,0) = 0 
							and bc.defaultbin <> 'Yes' and bc.cost < 25 or bc.cost IS NULL then 'Scrap'
							when isnull(tpu.lineCount,0) > 2 and bc.wmslocationid LIKE '%NONSTOCK%' then 'Do not add to van'
							when isnull(tpu.linecount,0) IN(0,1) and bc.wmslocationid LIKE '%NONSTOCK%' then 'Remove from van- do not add to warehouse'
							when isnull(tpu.linecount,0) IN(0,1,2) and bc.defaultbin <> 'Yes' then 'Remove from van- do not add to warehouse'
							when isnull(tpu.lineCount,0) IN(0,1,2) and bc.defaultbin = 'Yes' then 'Remove from van- add to warehouse'
							when isnull(tpu.linecount,0) > 2 and isnull(vi.availphys,0) > 0 then 'Keep on van'
							when isnull(tpu.lineCount,0) > 2 and isnull(vi.AvailPhys,0) = 0 then 'Add to van'


							else 'None'

				 end 'Recommendations'
				,bc.cost 'Cost'
				,case
				
				when bc.wmslocationid = 'NONSTOCK' then 'No'
				when bc.stockedstatus IS NOT NULL then 'Yes'
				else 'No'

				end 'Stocked in Main Inventory?'
				,isnull(bc.wmslocationid,'N/A') 'Bin'
				,isnull(bc.saledate,cast(bc.saledate AS nvarchar)) 'Last Sale Date'
				,cast(isnull(bc.availphys,0) AS int) 'Main Inv Count'
				,isnull(bc.min,0) 'Min'
				,isnull(bc.max,0) 'Max'	

from cte_TechPartUsage tpu
full join cte_VanInventory vi on tpu.itemid = vi.itemid
left join cte_BinAndCost bc on isnull(tpu.itemid,vi.itemid) = bc.itemid
order by 'Item id'